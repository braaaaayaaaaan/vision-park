"""Driver settlement access is separate from eligibility for new parking."""
from datetime import date
import re
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, Response
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from backend import database
from backend.auth import ApplicationUser, authenticated_user_id, require_administrator
from backend.payments import models, service


def require_payment_driver(user_id: Annotated[UUID, Depends(authenticated_user_id)]) -> ApplicationUser:
    try:
        row = database.get_auth_profile(str(user_id))
        if row is None:
            raise HTTPException(403, 'A driver profile is required.')
        user = ApplicationUser.model_validate(row)
        if user.id != user_id or user.role != 'driver':
            raise HTTPException(403, 'Driver payment access is required.')
        # No tenant or parking eligibility read: revoked access must not strand
        # an original owner. This dependency is never used by parking routes.
        return user
    except (database.DatabaseError, ValidationError):
        raise HTTPException(503, 'Driver payment access could not be verified.') from None


def no_store(response: Response):
    response.headers['Cache-Control'] = 'private, no-store'


router = APIRouter(dependencies=[Depends(no_store), Depends(require_payment_driver)])
admin_router = APIRouter(dependencies=[Depends(no_store), Depends(require_administrator)])
Driver = Annotated[ApplicationUser, Depends(require_payment_driver)]
Admin = Annotated[ApplicationUser, Depends(require_administrator)]
Key = Annotated[str, Header(alias='Idempotency-Key', min_length=1, max_length=64, pattern=r'^[A-Za-z0-9:_-]+$')]
Limit = Annotated[int, Query(ge=1, le=100)]
Offset = Annotated[int, Query(ge=0, le=1000000)]


async def body(request, model, optional=False):
    content = bytearray()
    async for chunk in request.stream():
        if len(content)+len(chunk) > 4096:
            raise HTTPException(413, detail={'code':'request_too_large','message':'Payment requests must be at most 4 KiB.'})
        content.extend(chunk)
    if optional and not content:
        return model()
    if request.headers.get('content-type','').split(';')[0].lower() != 'application/json':
        raise HTTPException(415, detail={'code':'json_required','message':'Use a JSON payment request.'})
    try:
        return model.model_validate_json(content)
    except ValidationError:
        # Never echo rejected PAN/CVV or other unexpected input in validation.
        raise HTTPException(422, detail={'code':'invalid_payment_request',
            'message':'Use the documented simulation fields, integer sen and current revisions. Do not submit real card details.'}) from None


@router.get('/wallet')
def wallet(driver: Driver):
    return service.wallet(driver.id)


@router.patch('/wallet/preferences')
async def preferences(request: Request, driver: Driver):
    change = await body(request, models.PreferencesInput)
    return await run_in_threadpool(service.preferences, driver.id, change)


@router.post('/wallet/mock-top-ups')
async def top_up(request: Request, driver: Driver, idempotency_key: Key):
    change = await body(request, models.TopUpInput)
    return await run_in_threadpool(service.top_up, driver.id, change, idempotency_key)


@router.get('/wallet/transactions')
def ledger(driver: Driver, limit: Limit = 30, offset: Offset = 0,
           entry_type: Literal['mock_top_up','parking_debit'] | None = None,
           start_date: date | None = None, end_date: date | None = None):
    return service.wallet_history(driver.id, limit, offset, entry_type, start_date, end_date)


@router.get('/requests')
def requests(driver: Driver, limit: Limit = 30, offset: Offset = 0,
             status: Literal['pending','open','paid','all'] = 'pending'):
    return service.requests(driver.id, limit, offset, status)


@router.get('/requests/{charge_id}')
def request_details(charge_id: UUID, driver: Driver):
    return service.request_details(driver.id, charge_id)


@router.post('/requests/{charge_id}/refresh-quote')
async def renew(charge_id: UUID, request: Request, driver: Driver):
    change = await body(request, models.QuoteInput)
    return await run_in_threadpool(service.renew, driver.id, charge_id, change)


@router.get('/gateway/card-profiles')
def profiles(driver: Driver):
    return service.card_profiles()


@router.post('/requests/{charge_id}/checkout')
async def checkout(charge_id: UUID, request: Request, driver: Driver, idempotency_key: Key):
    change = await body(request, models.CheckoutInput)
    return await run_in_threadpool(service.checkout, driver.id, charge_id, change, idempotency_key)


@router.post('/requests/{charge_id}/wallet-payment')
async def wallet_payment(charge_id: UUID, request: Request, driver: Driver, idempotency_key: Key):
    change = await body(request, models.WalletPaymentInput)
    return await run_in_threadpool(service.wallet_payment, driver.id, charge_id, change, idempotency_key)


@router.get('/attempts/by-key/{idempotency_key}')
def by_key(idempotency_key: str, driver: Driver):
    # Path value is checked without reflecting it; never put real credentials here.
    if not re.fullmatch(r'[A-Za-z0-9:_-]{1,64}', idempotency_key):
        raise HTTPException(422, 'Use a valid checkout idempotency key.')
    return service.attempt_by_key(driver.id, idempotency_key)


@router.get('/attempts/{attempt_id}')
def attempt(attempt_id: UUID, driver: Driver):
    return service.attempt_details(driver.id, attempt_id)


@router.post('/attempts/{attempt_id}/verify')
async def verify(attempt_id: UUID, request: Request, driver: Driver):
    await body(request, models.EmptyInput, optional=True)
    return await run_in_threadpool(service.verify, driver.id, attempt_id)


@router.post('/attempts/{attempt_id}/reconcile')
async def reconcile(attempt_id: UUID, request: Request, driver: Driver):
    await body(request, models.EmptyInput, optional=True)
    return await run_in_threadpool(service.verify, driver.id, attempt_id, True)


@router.get('/receipts')
def receipts(driver: Driver, limit: Limit = 30, offset: Offset = 0, start_date: date | None = None, end_date: date | None = None):
    return service.receipts(driver.id, limit, offset, start_date, end_date)


@router.get('/receipts/{attempt_id}')
def receipt(attempt_id: UUID, driver: Driver):
    return service.receipt(driver.id, attempt_id)


@admin_router.get('/tariffs')
def tariffs(admin: Admin, limit: Limit = 25, offset: Offset = 0):
    return service.tariffs(limit, offset)


@admin_router.post('/tariffs', status_code=201)
async def publish_tariff(request: Request, admin: Admin):
    change = await body(request, models.TariffInput)
    return await run_in_threadpool(service.publish_tariff, admin.id, change)


@admin_router.get('/transactions')
def transactions(admin: Admin, limit: Limit = 25, offset: Offset = 0,
                 status: models.AttemptStatus | None = None, method: models.PaymentMethod | None = None,
                 driver_id: UUID | None = None,
                 reference: Annotated[str, Query(max_length=100, pattern=r'^[A-Za-z0-9:_-]*$')] = '',
                 start_date: date | None = None, end_date: date | None = None):
    return service.transactions(limit, offset, status, method, driver_id, reference, start_date, end_date)


@admin_router.get('/transactions/{attempt_id}')
def transaction(attempt_id: UUID, admin: Admin):
    return service.transaction_details(attempt_id)


@admin_router.get('/summary')
def summary(admin: Admin, start_date: date | None = None, end_date: date | None = None):
    return service.summary(start_date, end_date)
