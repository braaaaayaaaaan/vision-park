"""Plain-text rejection reason validation shared by vehicle decisions."""

REJECTION_REASON_LIMIT = 500
_WHITESPACE = (' \t\n\r\v\f\x1c\x1d\x1e\x1f\x85\xa0\u1680'
               '\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a'
               '\u2028\u2029\u202f\u205f\u3000\ufeff')


def normalize_rejection_reason(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError('Enter a rejection reason.')
    value = value.replace('\r\n', '\n').replace('\r', '\n').strip(_WHITESPACE)
    if not value:
        raise ValueError('Enter a rejection reason.')
    if len(value) > REJECTION_REASON_LIMIT:
        raise ValueError('Use 500 characters or fewer for the rejection reason.')
    if any((ord(char) < 32 and char not in '\n\t') or ord(char) == 127 for char in value):
        raise ValueError('Use plain text without control characters for the rejection reason.')
    return value
