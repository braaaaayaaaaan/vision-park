"""Private administrator floor plans. No graph or allocation writes."""
from io import BytesIO
import logging
import warnings
from uuid import uuid4

from fastapi import HTTPException
from PIL import Image, ImageOps, UnidentifiedImageError, PngImagePlugin, JpegImagePlugin

from backend import database

BUCKET = 'parking-floor-plans'
MAX_BYTES = 10 * 1024 * 1024
MAX_PIXELS = 20_000_000
logger = logging.getLogger(__name__)

def size_error(code):
    return HTTPException(413, {'code': code})


def process_image(data):
    if not data or len(data) > MAX_BYTES:
        raise size_error('floor_plan_upload_too_large')
    # ANPR's Ultralytics dependency patches Image.open to install optional codecs
    # on decode failures. Use only explicit Pillow decoders for this upload path.
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        decoder = PngImagePlugin.PngImageFile
    elif data.startswith(b'\xff\xd8\xff'):
        decoder = JpegImagePlugin.jpeg_factory
    else:
        raise HTTPException(415, 'Use a static PNG or JPEG image.')
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with decoder(BytesIO(data)) as image:
                if image.format not in ('PNG', 'JPEG') or getattr(image, 'n_frames', 1) != 1:
                    raise HTTPException(415, 'Use a static PNG or JPEG image.')
                if image.width * image.height > MAX_PIXELS:
                    raise size_error('floor_plan_pixels_too_large')
                image.verify()
            with decoder(BytesIO(data)) as image:
                image.load()
                normalized = ImageOps.exif_transpose(image)
                # Rebuild pixels to strip EXIF and other untrusted metadata.
                mode = 'RGBA' if 'A' in normalized.getbands() or 'transparency' in normalized.info else 'RGB'
                pixels = normalized.convert(mode)
                clean = Image.new(mode, pixels.size)
                clean.paste(pixels)
                output = BytesIO()
                clean.save(output, format='PNG')
                encoded = output.getvalue()
                if len(encoded) > MAX_BYTES:
                    raise size_error('floor_plan_processed_too_large')
                return encoded, clean.width, clean.height
    except HTTPException:
        raise
    except (Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise size_error('floor_plan_pixels_too_large') from None
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError):
        raise HTTPException(422, 'The image is corrupt or cannot be decoded.') from None


def storage():
    return database.get_supabase().storage.from_(BUCKET)


def metadata(level_id):
    rows = database._execute(database.get_supabase().table('parking_level_floor_plans')
                             .select('*').eq('level_id', level_id)).data
    return rows[0] if rows else None


def listing():
    rows = []
    while True:
        page = database._execute(database.get_supabase().table('parking_level_floor_plans')
                                 .select('*').order('level_id').range(len(rows), len(rows) + 499)).data
        if not page:
            break
        rows.extend(page)
    plans = {row['level_id']: row for row in rows}
    return {'levels': [{**level, 'floor_plan': plans.get(level['id'])}
                       for level in sorted(database.get_levels(), key=lambda row: (row['level_number'], row['id']))]}


def cleanup(key):
    """Only immutable, unreferenced objects; errors leave an orphan for reconciliation."""
    if not key:
        return
    try:
        referenced = database._execute(database.get_supabase().table('parking_level_floor_plans')
                                       .select('level_id').eq('storage_object_key', key)).data
        if not referenced:
            storage().remove([key])
    except Exception:
        logger.warning('Floor-plan object cleanup deferred for reconciliation.')


def upload(level_id, admin_id, expected_revision, data):
    if not any(row['id'] == level_id for row in database.get_levels()):
        raise HTTPException(404, 'Parking level not found.')
    current = metadata(level_id)
    if (current['revision'] if current else 0) != expected_revision:
        raise HTTPException(409, 'Floor plan changed. Refresh before replacing it.')
    image, width, height = process_image(data)
    key = f'{level_id}/{uuid4()}.png'
    try:
        storage().upload(key, image, {'content-type': 'image/png', 'upsert': 'false'})
    except Exception:
        # No metadata write has been attempted, so this unique key cannot be current.
        cleanup(key)
        raise HTTPException(503, 'Image storage is unavailable. Please retry.') from None
    try:
        result = database._execute(database.get_supabase().rpc('replace_parking_floor_plan', {
            'p_admin_id': admin_id, 'p_level_id': level_id, 'p_expected_revision': expected_revision,
            'p_key': key, 'p_width': width, 'p_height': height,
        })).data
    except Exception:
        # Commit outcome unknown: never delete the new object on an ambiguous RPC failure.
        logger.warning('Floor-plan save outcome unknown; retain object for reconciliation.')
        raise HTTPException(503, 'Save could not be confirmed. Refresh before retrying.') from None
    if not isinstance(result, dict):
        raise HTTPException(503, 'Save could not be confirmed. Refresh before retrying.')
    if result.get('status') != 'saved':
        if result.get('status') in ('missing', 'forbidden', 'conflict'):
            cleanup(key)
        code, message = {
            'missing': (404, 'Parking level not found.'),
            'forbidden': (403, 'Administrator access is required.'),
            'conflict': (409, 'Floor plan changed. Refresh before replacing it.'),
        }.get(result.get('status'), (503, 'Save could not be confirmed. Refresh before retrying.'))
        raise HTTPException(code, message)
    cleanup(result.get('old_key'))
    return result['floor_plan']


def image_bytes(level_id, expected_revision=None):
    plan = metadata(level_id)
    if not plan:
        raise HTTPException(404, 'No floor plan is available for this level.')
    if expected_revision is not None and plan['revision'] != expected_revision:
        raise HTTPException(409, 'Floor plan changed. Refresh before viewing it.')
    try:
        return storage().download(plan['storage_object_key'])
    except Exception:
        raise HTTPException(503, 'Floor plan image is unavailable. Refresh and retry.') from None
