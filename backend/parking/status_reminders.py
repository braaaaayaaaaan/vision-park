"""Persisted, driver-owned in-app status requests; never change parking state."""
from typing import Literal
from uuid import UUID

from fastapi import HTTPException
from pydantic import AwareDatetime, BaseModel, ConfigDict, model_validator

from backend import database

MESSAGE = 'Your vehicle has remained in the parking building past midnight. Please confirm your status.'


class Reminder(BaseModel):
    id: UUID
    session_id: UUID
    plate_number: str
    entry_time: AwareDatetime
    sent_at: AwareDatetime
    response: Literal['still_parked', 'already_left'] | None
    responded_at: AwareDatetime | None
    message: str = MESSAGE

    @model_validator(mode='after')
    def response_matches_time(self):
        if (self.response is None) != (self.responded_at is None):
            raise ValueError('Inconsistent reminder response.')
        return self


class SendReminder(BaseModel):
    model_config = ConfigDict(extra='forbid')
    session_id: UUID
    request_id: UUID


class DriverResponse(BaseModel):
    model_config = ConfigDict(extra='forbid')
    response: Literal['still_parked', 'already_left']


def operation(name, params, expected):
    result = database.parking_reminder_rpc(name, params)
    if not isinstance(result, dict):
        raise database.DatabaseError('Invalid reminder result.')
    errors = {
        'forbidden': (403, 'This account cannot access parking reminders.'),
        'not_found': (404, 'Parking reminder or session not found.'),
        'invalid': (422, 'Use a valid parking reminder request.'),
        'conflict': (409, 'The parking session or reminder changed. Refresh before trying again.'),
        'driver_unavailable': (409, 'The session driver cannot currently receive reminders.'),
        'cooldown': (429, 'A reminder was sent recently. Wait 15 minutes between reminders for this session.'),
    }
    if result.get('status') in errors:
        raise HTTPException(*errors[result['status']])
    if result.get('status') != expected:
        raise database.DatabaseError('Unconfirmed reminder result.')
    return result


def read(actor_id, session_ids=None):
    data = operation('read_parking_status_reminders', {'p_actor_id': actor_id, 'p_session_ids': session_ids}, 'read')
    return {'reminders': [Reminder.model_validate(row) for row in data['reminders']]}


def send(admin_id, change):
    operation('send_parking_status_reminder', {'p_admin_id': admin_id, 'p_session_id': str(change.session_id),
        'p_request_id': str(change.request_id)}, 'sent')
    return {'status': 'sent', **read(admin_id, [str(change.session_id)])}


def respond(driver_id, reminder_id, change):
    operation('respond_parking_status_reminder', {'p_driver_id': driver_id, 'p_reminder_id': reminder_id,
        'p_response': change.response}, 'recorded')
    return {'status': 'recorded'}
