from fastapi import FastAPI
import logging
from time import perf_counter
from backend.api.auth import router as auth_router
from backend.api.admin import router as admin_router
from backend.api.anpr import router as anpr_router
from backend.api.cameras import router as cameras_router
from backend.api.parking import router as parking_router
from backend.api.vehicles import router as vehicles_router
from backend.api.history import router as history_router
from backend.api.payments import router as payments_router, admin_router as admin_payments_router
from backend.anpr.persistence import configure_diagnostics

configure_diagnostics()

# initialise the backend application
app = FastAPI()


@app.middleware('http')
async def unavailable_diagnostic(request, call_next):
    started = perf_counter()
    response = await call_next(request)
    if response.status_code == 503:
        # Route templates only: no raw paths, query strings, bodies or identities.
        route = getattr(request.scope.get('route'), 'path', 'unmatched')
        logging.getLogger('uvicorn.error').warning(
            'api_unavailable route=%s elapsed_ms=%.2f', route, (perf_counter() - started) * 1000)
    return response

#note: this is for testing the api endpoint (root level)
@app.get("/")
def root():
    return {"message": "the backend is running"}

# include all the necessary routers to expose api endpoints
app.include_router(anpr_router, prefix="/anpr", tags=["ANPR"])
app.include_router(parking_router, prefix="/parking", tags=["Parking"])
app.include_router(history_router, prefix="/parking", tags=["Parking"])
app.include_router(vehicles_router, prefix="/vehicles", tags=["Vehicles"])
app.include_router(auth_router, prefix="/auth", tags=["Authentication"])
app.include_router(admin_router, prefix="/admin", tags=["Administration"])
app.include_router(cameras_router, prefix="/admin/cameras", tags=["Camera Management"])
app.include_router(payments_router, prefix="/payments", tags=["Payments"])
app.include_router(admin_payments_router, prefix="/admin/payments", tags=["Administrator Payments"])
