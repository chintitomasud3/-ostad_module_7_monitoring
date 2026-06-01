#!/bin/bash

set -e  # error hole stop korbe

echo "🔄 Updating system..."
sudo apt update

echo "🐍 Installing Python & tools..."
sudo apt install -y python3 python3-pip python3-venv
cd ..
echo "📁 Creating project directory..."
mkdir -p Backend
cd Backend

echo "⚙️ Creating virtual environment..."
python3 -m venv venv

echo "🚀 Activating virtual environment..."
source venv/bin/activate

echo "📦 Installing dependencies..."
pip install --upgrade pip
pip install fastapi uvicorn motor pydantic

echo "📝 Creating main.py..."

cat <<EOF > main.py
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from motor.motor_asyncio import AsyncIOMotorClient
from bson import ObjectId

app = FastAPI()

# ---------------- CORS ----------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------- MongoDB ----------------
MONGO_URL = "mongodb://10.0.13.224:27017"

client = AsyncIOMotorClient(MONGO_URL)
db = client.my_database
collection = db.users

# ---------------- Model ----------------
class User(BaseModel):
    name: str
    email: str
    age: int | None = None

# ---------------- HTML PAGE ----------------
@app.get("/", response_class=HTMLResponse)
async def home():
    return "<h2>FastAPI Running Successfully 🚀</h2>"

# ---------------- CREATE USER ----------------
@app.post("/users")
async def create_user(user: User):
    result = await collection.insert_one(user.dict())
    return {
        "id": str(result.inserted_id),
        "message": "User created successfully"
    }

# ---------------- GET ALL USERS ----------------
@app.get("/users")
async def get_users():
    users = []
    cursor = collection.find()

    async for user in cursor:
        user["_id"] = str(user["_id"])
        users.append(user)

    return users

# ---------------- GET SINGLE USER ----------------
@app.get("/users/{user_id}")
async def get_user(user_id: str):
    user = await collection.find_one({"_id": ObjectId(user_id)})

    if user:
        user["_id"] = str(user["_id"])
        return user

    return {"message": "User not found"}
EOF

echo "🔥 Start the server using. # uvicorn main:app --host 0.0.0.0 --port 8000.."

# uvicorn main:app --host 0.0.0.0 --port 8000
