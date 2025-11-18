from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
from dotenv import load_dotenv
from typing import Optional, List, Dict
import json
import uuid
from datetime import datetime
import boto3
from botocore.exceptions import ClientError
from context import prompt  # Your system prompt generator

# Load environment variables
load_dotenv()

app = FastAPI()

# Configure CORS
origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["*"],  # Allow GET, POST, OPTIONS, etc.
    allow_headers=["*"],
)

# AWS Bedrock client
bedrock_client = boto3.client(
    service_name="bedrock-runtime",
    region_name=os.getenv("DEFAULT_AWS_REGION", "eu-west-1")
)

BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "amazon.nova-micro-v1:0")

# Memory configuration
USE_S3 = os.getenv("USE_S3", "false").lower() == "true"
S3_BUCKET = os.getenv("S3_BUCKET", "")
MEMORY_DIR = os.getenv("MEMORY_DIR", "/tmp")  # Lambda writable directory

if USE_S3:
    s3_client = boto3.client("s3")


# Models
class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None


class ChatResponse(BaseModel):
    response: str
    session_id: str


# Memory functions
def get_memory_path(session_id: str) -> str:
    return f"{session_id}.json"


def load_conversation(session_id: str) -> List[Dict]:
    if USE_S3:
        try:
            response = s3_client.get_object(Bucket=S3_BUCKET, Key=get_memory_path(session_id))
            return json.loads(response["Body"].read().decode("utf-8"))
        except ClientError as e:
            if e.response["Error"]["Code"] == "NoSuchKey":
                return []
            raise
    else:
        file_path = os.path.join(MEMORY_DIR, get_memory_path(session_id))
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                return json.load(f)
        return []


def save_conversation(session_id: str, messages: List[Dict]):
    if USE_S3:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=get_memory_path(session_id),
            Body=json.dumps(messages, indent=2),
            ContentType="application/json",
        )
    else:
        os.makedirs(MEMORY_DIR, exist_ok=True)
        file_path = os.path.join(MEMORY_DIR, get_memory_path(session_id))
        with open(file_path, "w") as f:
            json.dump(messages, f, indent=2)


# Bedrock call
def call_bedrock(conversation: List[Dict], user_message: str) -> str:
    messages = [{"role": "user", "content": [{"text": f"System: {prompt()}"}]}]

    for msg in conversation[-20:]:
        messages.append({"role": msg["role"], "content": [{"text": msg["content"]}]})

    messages.append({"role": "user", "content": [{"text": user_message}]})

    try:
        response = bedrock_client.converse(
            modelId=BEDROCK_MODEL_ID,
            messages=messages,
            inferenceConfig={"maxTokens": 2000, "temperature": 0.7, "topP": 0.9},
        )
        return response["output"]["message"]["content"][0]["text"]
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "ValidationException":
            raise HTTPException(status_code=400, detail="Invalid message format for Bedrock")
        elif code == "AccessDeniedException":
            raise HTTPException(status_code=403, detail="Access denied to Bedrock model")
        else:
            raise HTTPException(status_code=500, detail=str(e))


# Routes
@app.get("/")
async def root():
    return {
        "message": "AI Digital Twin API (Powered by AWS Bedrock)",
        "memory_enabled": True,
        "storage": "S3" if USE_S3 else "local",
        "ai_model": BEDROCK_MODEL_ID,
    }


@app.get("/health")
async def health_check():
    return {"status": "healthy", "use_s3": USE_S3, "bedrock_model": BEDROCK_MODEL_ID}


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    session_id = request.session_id or str(uuid.uuid4())
    conversation = load_conversation(session_id)
    assistant_response = call_bedrock(conversation, request.message)
    conversation.append({"role": "user", "content": request.message, "timestamp": datetime.now().isoformat()})
    conversation.append({"role": "assistant", "content": assistant_response, "timestamp": datetime.now().isoformat()})
    save_conversation(session_id, conversation)
    return ChatResponse(response=assistant_response, session_id=session_id)


@app.get("/conversation/{session_id}")
async def get_conversation(session_id: str):
    conversation = load_conversation(session_id)
    return {"session_id": session_id, "messages": conversation}


# Optional: handle OPTIONS (preflight) explicitly if needed
@app.options("/{full_path:path}")
async def preflight(full_path: str, request: Request):
    return {"status": "ok"}  # FastAPI + CORSMiddleware already handle headers

