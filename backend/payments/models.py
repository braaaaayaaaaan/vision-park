"""Money is integer sen. No request accepts a PAN, CVV, amount override or paid flag."""
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StrictBool, StrictInt, model_validator

Money = Annotated[StrictInt, Field(ge=0, le=9_000_000_000_000)]
Revision = Annotated[StrictInt, Field(ge=1, le=9_007_199_254_740_990)]
AttemptStatus = Literal['processing', 'unknown', 'succeeded', 'declined', 'failed']
PaymentMethod = Literal['wallet', 'mock_card', 'zero']
CardProfile = Literal['vp_demo_approved', 'vp_demo_declined', 'vp_demo_failed',
                      'vp_demo_interrupted', 'vp_demo_pending']


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid')


class EmptyInput(Input):
    pass


class PreferencesInput(Input):
    expected_revision: Revision
    automatic_payment_enabled: StrictBool


class TopUpInput(Input):
    amount_sen: Annotated[StrictInt, Field(ge=1, le=100_000_000)]


class QuoteInput(Input):
    expected_revision: Revision


class WalletPaymentInput(Input):
    quote_revision: Revision


class CheckoutInput(WalletPaymentInput):
    card_profile: CardProfile


class TariffInput(Input):
    expected_version: Annotated[StrictInt, Field(ge=0, le=9_007_199_254_740_989)]
    initial_duration_minutes: Annotated[StrictInt, Field(ge=1, le=1440)]
    initial_charge_sen: Annotated[StrictInt, Field(ge=0, le=1_000_000_000)]
    subsequent_hourly_rate_sen: Annotated[StrictInt, Field(ge=0, le=1_000_000_000)]
    rounding_minutes: Literal[1, 15, 30, 60]
    grace_minutes: Annotated[StrictInt, Field(ge=0, le=1440)]
    maximum_charge_sen: Annotated[StrictInt, Field(ge=0, le=1_000_000_000)] | None = None
    effective_from: AwareDatetime | None = None

    @model_validator(mode='before')
    @classmethod
    def integer_rounding(cls, value):
        if isinstance(value, dict) and type(value.get('rounding_minutes')) is not int:
            raise ValueError('Use an integer rounding increment.')
        return value


class Wallet(BaseModel):
    user_id: UUID
    balance_sen: Money = 0
    automatic_payment_enabled: StrictBool = False
    preference_revision: Revision = 1
    updated_at: AwareDatetime | None = None


class LedgerEntry(BaseModel):
    id: UUID
    user_id: UUID
    payment_attempt_id: UUID | None
    entry_type: Literal['mock_top_up', 'parking_debit']
    amount_sen: Annotated[StrictInt, Field(gt=0)]
    balance_after_sen: Money
    created_at: AwareDatetime

    @model_validator(mode='after')
    def debit_reference(self):
        if (self.entry_type == 'parking_debit') != (self.payment_attempt_id is not None):
            raise ValueError('Invalid ledger reference')
        return self


class Tariff(BaseModel):
    id: UUID
    version_number: Revision
    effective_from: AwareDatetime
    initial_duration_minutes: Annotated[StrictInt, Field(ge=1, le=1440)]
    initial_charge_sen: Money
    subsequent_hourly_rate_sen: Money
    rounding_minutes: Literal[1, 15, 30, 60]
    grace_minutes: Annotated[StrictInt, Field(ge=0, le=1440)]
    maximum_charge_sen: Money | None
    currency: Literal['MYR']
    published_at: AwareDatetime
    published_by: UUID


class VehicleLabel(BaseModel):
    id: UUID
    plate_number: str


class LevelLabel(BaseModel):
    id: UUID
    name: str


class ZoneLabel(BaseModel):
    id: UUID
    name: str
    level: LevelLabel | None = None


class CompanyLabel(BaseModel):
    id: UUID
    name: str


class DriverLabel(BaseModel):
    id: UUID
    full_name: str
    tenant_id: UUID | None = None
    tenant: CompanyLabel | None = None

    @model_validator(mode='after')
    def company_identity(self):
        if self.tenant and self.tenant.id != self.tenant_id:
            raise ValueError('Driver company identity mismatch')
        return self


class SessionContext(BaseModel):
    id: UUID
    vehicle_id: UUID
    user_id: UUID
    zone_id: UUID
    entry_time: AwareDatetime
    parking_confirmed_at: AwareDatetime | None
    exit_time: AwareDatetime | None
    status: Literal['allocated', 'occupied', 'completed', 'cancelled']
    current_vehicle: VehicleLabel | None = None
    current_zone: ZoneLabel | None = None

    @model_validator(mode='after')
    def label_identity(self):
        if ((self.current_vehicle and self.current_vehicle.id != self.vehicle_id)
                or (self.current_zone and self.current_zone.id != self.zone_id)):
            raise ValueError('Session context identity mismatch')
        return self


class Charge(BaseModel):
    id: UUID
    session_id: UUID
    user_id: UUID
    tariff_version_id: UUID
    status: Literal['open', 'pending', 'paid']
    first_exit_detected_at: AwareDatetime | None
    quote_revision: Annotated[StrictInt, Field(ge=0)]
    quoted_at: AwareDatetime | None
    quoted_through_at: AwareDatetime | None
    quote_expires_at: AwareDatetime | None
    amount_sen: Money | None
    currency: Literal['MYR']
    calculation_snapshot: dict
    created_at: AwareDatetime
    paid_at: AwareDatetime | None
    tariff: Tariff
    session: SessionContext
    current_driver: DriverLabel | None = None

    @model_validator(mode='after')
    def proof(self):
        if (self.tariff.id != self.tariff_version_id or self.session.id != self.session_id
                or self.session.user_id != self.user_id or (self.current_driver and self.current_driver.id != self.user_id)):
            raise ValueError('Charge identity mismatch')
        if self.status == 'open':
            if self.quote_revision != 0 or self.amount_sen is not None or self.first_exit_detected_at is not None:
                raise ValueError('Unquoted charge has a price')
        else:
            if (self.amount_sen is None or self.quote_revision < 1 or self.first_exit_detected_at is None
                    or self.quoted_at is None or self.quoted_through_at is None or self.quote_expires_at is None
                    or not self.session.entry_time <= self.first_exit_detected_at <= self.quoted_through_at <= self.quoted_at < self.quote_expires_at
                    or type(self.calculation_snapshot.get('amount_sen')) is not int
                    or self.calculation_snapshot['amount_sen'] != self.amount_sen
                    or self.calculation_snapshot.get('currency') != 'MYR'
                    or self.calculation_snapshot.get('tariff_version') != self.tariff.version_number):
                raise ValueError('Invalid frozen quotation')
        if self.status == 'paid':
            if self.paid_at is None or self.session.status != 'completed' or self.session.exit_time != self.paid_at:
                raise ValueError('Payment completion proof missing')
        elif self.paid_at is not None or self.session.status not in ('allocated', 'occupied'):
            raise ValueError('Unpaid session is not active')
        return self


class Attempt(BaseModel):
    id: UUID
    charge_id: UUID
    quote_revision: Revision
    method: PaymentMethod
    status: AttemptStatus
    amount_sen: Money
    currency: Literal['MYR']
    provider_reference: str = Field(min_length=1, max_length=128)
    failure_code: str | None = None
    created_at: AwareDatetime
    updated_at: AwareDatetime
    settled_at: AwareDatetime | None
    receipt_number: str | None

    @model_validator(mode='after')
    def settlement(self):
        if self.status == 'succeeded':
            if not self.receipt_number or self.settled_at is None or self.settled_at < self.created_at:
                raise ValueError('Missing settlement proof')
        elif self.settled_at is not None or self.receipt_number is not None:
            raise ValueError('Unsuccessful attempt has a receipt')
        if self.method == 'zero' and self.amount_sen != 0:
            raise ValueError('Invalid zero settlement')
        return self
