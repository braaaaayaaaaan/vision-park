from fastapi import FastAPI
from backend.api.auth import router as auth_router
from backend.api.admin import router as admin_router
from backend.api.anpr import router as anpr_router
from backend.api.parking import router as parking_router
from backend.api.vehicles import router as vehicles_router
from backend.api.history import router as history_router
from backend.api.payments import router as payments_router, admin_router as admin_payments_router

# initialise the backend application
app = FastAPI()

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
app.include_router(payments_router, prefix="/payments", tags=["Simulated Payments"])
app.include_router(admin_payments_router, prefix="/admin/payments", tags=["Administrator Payments"])
