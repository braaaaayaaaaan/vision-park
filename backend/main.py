from fastapi import FastAPI
from backend.api.auth import router as auth_router
from backend.api.admin import router as admin_router
from backend.api.anpr import router as anpr_router
from backend.api.parking import router as parking_router

# initialise the backend application
app = FastAPI()

#note: this is for testing the api endpoint (root level)
@app.get("/")
def root():
    return {"message": "the backend is running"}

# include all the necessary routers to expose api endpoints
app.include_router(anpr_router, prefix="/anpr", tags=["ANPR"])
app.include_router(parking_router, prefix="/parking", tags=["Parking"])
app.include_router(auth_router, prefix="/auth", tags=["Authentication"])
app.include_router(admin_router, prefix="/admin", tags=["Administration"])
