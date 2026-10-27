"""Fictional provider adapter. Only 021 decides/commits payment outcomes."""
from backend.payments import data

PROFILES = {
    'vp_demo_approved': dict(label='VisionPark Demo Card', last_four='1001', hint='Simulates approval.', scenario='success'),
    'vp_demo_declined': dict(label='VisionPark Decline Card', last_four='1002', hint='Simulates a declined payment.', scenario='decline'),
    'vp_demo_failed': dict(label='VisionPark Failure Card', last_four='1003', hint='Simulates a provider failure.', scenario='failure'),
    'vp_demo_interrupted': dict(label='VisionPark Interrupted Card', last_four='1004', hint='Simulates an interrupted response requiring reconciliation.', scenario='timeout_success'),
    'vp_demo_pending': dict(label='VisionPark Pending Card', last_four='1005', hint='Simulates a pending decision requiring reconciliation.', scenario='timeout_pending'),
}


def profiles():
    return [dict(id=key, **{field: row[field] for field in ('label', 'last_four', 'hint')}) for key, row in PROFILES.items()]


def profile_id(scenario):
    return next((key for key, row in PROFILES.items() if row['scenario'] == scenario), None)


def begin(user_id, charge_id, quote_revision, key, profile):
    return data.rpc('begin_mock_parking_payment', dict(p_user_id=user_id, p_charge_id=charge_id,
        p_quote_revision=quote_revision, p_idempotency_key=key, p_scenario=PROFILES[profile]['scenario']))


def verify(user_id, attempt_id, reconcile=False):
    return data.rpc('settle_mock_parking_payment', dict(p_user_id=user_id, p_attempt_id=attempt_id, p_reconcile=reconcile))
