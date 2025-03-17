from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import json

from app.services.ai_service import AIService

router = APIRouter(prefix="/ai", tags=["ai"])

class ChatRequest(BaseModel):
    message: str
    user_id: str = None  # Optional for now, will be required later

class ChatResponse(BaseModel):
    response: str

@router.post("/chat", response_model=ChatResponse)
async def process_chat(request: ChatRequest):
    try:
        ai_service = AIService()
        
        # Get the message response
        message_text = await ai_service.generate_response(
            message=request.message,
            user_id=request.user_id
        )
        
        print("\n=== AI API MESSAGE RESPONSE ===")
        print(message_text)
        print("==============================\n")
        
        # Check if this is a checklist request
        needs_checklist = await ai_service.should_generate_checklist(
            message=request.message
        )
        
        # If this is a checklist request, generate checklist items
        checklist_data = {}
        if needs_checklist:
            checklist_result = await ai_service.generate_checklist(
                message=request.message
            )
            if checklist_result:
                checklist_data = checklist_result
            
            print("\n=== AI API CHECKLIST DATA ===")
            print(json.dumps(checklist_data, indent=2) if checklist_data else "No checklist data generated")
            print("============================\n")
        
        # Format the response in the expected structure
        response_data = {
            "message": message_text,
            "checklists": checklist_data
        }
        
        print("\n=== AI API FINAL RESPONSE ===")
        print(json.dumps(response_data, indent=2))
        print("===========================\n")
        
        return ChatResponse(response=json.dumps(response_data))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) 