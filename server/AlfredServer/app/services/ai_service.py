import os
import re
import json
from typing import Optional, List, Dict, Any, Tuple, Union
from openai import OpenAI
from datetime import datetime, timedelta, timezone
from pydantic import BaseModel

# =============================================================================
# AGENT INSTRUCTIONS - Centralized for easy editing
# =============================================================================

# Classification agent instructions
QUERY_CLASSIFIER_INSTRUCTIONS = """You are a query classifier that determines if a user message requires simple or complex processing.
SIMPLE: Standard conversation, greetings, factual questions, short responses.
COMPLEX: Reasoning, planning, updating checklists, multi-step tasks, detailed explanations.

Respond with ONLY one word: either 'simple' or 'complex'."""

CHECKLIST_CLASSIFIER_INSTRUCTIONS = """You are a classifier that determines if a response should include checklist items.
Today is {current_date} and the current time is {current_time}.
Determine if the user's message is requesting or implying the creation of:
- A to-do list or checklist
- Task reminders
- Action items
- Scheduled activities
- Any form of trackable items that should be added to their planner

Respond with ONLY 'yes' if checklist items should be generated, or 'no' if not."""

# Message agent instructions
MESSAGE_AGENT_BASE_INSTRUCTIONS = """You are Alfred, a personal assistant currently texting {user_full_name}.
Today is {current_date} and the current time is {current_time}.
Your ultimate goal is to make the {user_full_name}'s life better in the long term.
Be as concise, casual, reserved, and practical as you can. Remove all fluff and redundancy.
One word responses are preferred when appropriate."""

MESSAGE_AGENT_CHECKLIST_INSTRUCTIONS = """
The user is asking about tasks, reminders, or to-do items.
Respond with a brief acknowledgment that you're updating their planner.
DO NOT include any details about the tasks or plans - those will be handled separately.
Keep your response under 30 words, just acknowledging the update."""

# Checklist agent instructions
CHECKLIST_AGENT_INSTRUCTIONS = """You are a checklist creation specialist.
Today is {current_day}, {current_date} and the current time is {current_time}.
Your task is to create well-structured checklist items based on the user's request.
Organize items by date in YYYY-MM-DD format.
For complicated tasks, or upon the user's request, provide meaningful notes that summarize the tasks,
provide broader context, and include relevant inspirational quotes or wisdom that relate to the day's
activities. Do not add notes for simple tasks.
Each item should have a clear title and, when requested (generally don't), a notification time in HH:MM format.
Be specific, practical, and thorough in creating these checklist items.
DO NOT over complicate simple tasks. A single item per day with a title is preffered.
"""

CHECKLIST_FORMAT_INSTRUCTIONS = """Please format your response as a JSON object with the following structure:
{
    "checklists": {
        "YYYY-MM-DD": {
            "notes": "Notes summarizing the day's tasks",
            "items": [
            {
                "title": "Task description",
                "notification": "HH:MM or null"
            }
            ]
        }
    }
}

Use the date in YYYY-MM-DD format as the key in the checklists object."""

# Pydantic models for structured responses
class ChecklistItem(BaseModel):
    title: str
    notification: Optional[str]

class ChecklistDay(BaseModel):
    notes: str
    items: List[ChecklistItem]

class AlfredResponse(BaseModel):
    message: str
    checklists: Optional[Dict[str, ChecklistDay]]

class AIService:
    def __init__(self):
        # Initialize your AI service with the new OpenAI client
        api_key = os.getenv("OPENAI_API_KEY", "")
        self.client = OpenAI(api_key=api_key)
        
    async def classify_query(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None) -> str:
        """
        Classify the user's query as either 'simple' or 'complex'
        
        Simple: Standard conversation, greetings, basic questions
        Complex: Reasoning, planning, updating checklists, multi-step tasks
        """
        try:
            # Get current date and time
            now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for classification with date/time
            classification_prompt = QUERY_CLASSIFIER_INSTRUCTIONS.format(
                current_date=current_date,
                current_time=current_time
            )
            
            # Prepare context from recent message history (last 3 messages)
            context_messages = []
            if message_history:
                # Get the last 3 messages for context
                recent_messages = message_history[-3:] if len(message_history) > 3 else message_history
                for msg in recent_messages:
                    if "role" in msg and "content" in msg:
                        context_messages.append({"role": msg["role"], "content": msg["content"]})
            
            # Create messages array for classification
            classification_messages = [
                {"role": "system", "content": classification_prompt}
            ]
            
            # Add context messages if available
            if context_messages:
                classification_messages.extend(context_messages)
            
            # Add the current message
            classification_messages.append({"role": "user", "content": message})
            
            # Use GPT-4o-mini for classification - faster and still accurate for this task
            response = self.client.chat.completions.create(
                model="gpt-4o-mini-2024-07-18",  # Updated model name
                messages=classification_messages,
                temperature=0.3,  # Lower temperature for more consistent classification
                max_tokens=5  # We only need a single word response
            )
            
            # Get the classification result
            result = response.choices[0].message.content.strip().lower()
            
            # Ensure we get either 'simple' or 'complex'
            if "complex" in result:
                return "complex"
            else:
                return "simple"  # Default to 'simple' for any other response
                
        except Exception as e:
            print(f"Error classifying query: {e}")
            # Default to 'complex' on error to ensure better responses
            return "complex"
    
    async def should_generate_checklist(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None) -> bool:
        """
        Determine if the response should include checklist items
        
        Returns True if the user's query is related to tasks, todos, or checklists
        """
        try:
            # Get current date and time
            now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for checklist classification
            classification_prompt = CHECKLIST_CLASSIFIER_INSTRUCTIONS.format(
                current_date=current_date,
                current_time=current_time
            )
            
            # Prepare context from recent message history (last 3 messages)
            context_messages = []
            if message_history:
                # Get the last 3 messages for context
                recent_messages = message_history[-3:] if len(message_history) > 3 else message_history
                for msg in recent_messages:
                    if "role" in msg and "content" in msg:
                        context_messages.append({"role": msg["role"], "content": msg["content"]})
            
            # Create messages array for classification
            classification_messages = [
                {"role": "system", "content": classification_prompt}
            ]
            
            # Add context messages if available
            if context_messages:
                classification_messages.extend(context_messages)
            
            # Add the current message
            classification_messages.append({"role": "user", "content": message})
            
            # Use GPT-4o-mini for classification - faster and still accurate for this task
            response = self.client.chat.completions.create(
                model="gpt-4o-mini-2024-07-18",  # Updated model name
                messages=classification_messages,
                temperature=0.3,  # Lower temperature for more consistent classification
                max_tokens=5  # We only need a single word response
            )
            
            # Get the classification result
            result = response.choices[0].message.content.strip().lower()
            
            # Return True if the result contains 'yes'
            return 'yes' in result
                
        except Exception as e:
            print(f"Error classifying for checklist generation: {e}")
            # Default to False on error
            return False
        
    async def generate_response(self, message: str, user_id: Optional[str] = None, message_history: Optional[List[Dict[str, Any]]] = None, user_full_name: Optional[str] = None) -> str:
        """
        Generate an AI response to the user's message, optionally using message history for context.
        This method only handles the conversational response, not checklist generation.
        """
        try:
            # First, classify the query
            query_type = await self.classify_query(message, message_history)
            print(f"Query classified as: {query_type}")
            
            # Determine if we should generate checklist items
            needs_checklist = await self.should_generate_checklist(message, message_history)
            print(f"Needs checklist: {needs_checklist}")
            
            # Get current date and time
            now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Prepare messages for the API - only include role and content fields
            api_messages = []
            
            # Create a personalized system message with date/time
            system_message = MESSAGE_AGENT_BASE_INSTRUCTIONS.format(
                user_full_name=user_full_name or 'the user',
                current_date=current_date,
                current_time=current_time
            )
            
            # If this is a checklist request, modify the system message to be very brief
            instruction_type = "Base Instructions"
            if needs_checklist:
                system_message += MESSAGE_AGENT_CHECKLIST_INSTRUCTIONS
                instruction_type = "Checklist Instructions"
            
            # Add system message
            api_messages.append({"role": "system", "content": system_message})
            
            # Add message history if provided, with constraints:
            # 1. Only the last 30 messages maximum
            # 2. Only messages from the last 2 hours
            if message_history:
                # Filter out system messages from history to avoid conflicts
                filtered_history = [msg for msg in message_history if msg.get("role") != "system"]
                
                # Apply time constraint - only messages from the last 2 hours
                # Use UTC timezone for consistency
                two_hours_ago = datetime.now(timezone.utc) - timedelta(hours=2)
                recent_history = []
                
                for msg in filtered_history:
                    # Check if the message has a timestamp
                    if "timestamp" in msg:
                        msg_time = None
                        # Try to parse the timestamp
                        try:
                            if isinstance(msg["timestamp"], str):
                                # Parse string to datetime with timezone awareness
                                msg_time = datetime.fromisoformat(msg["timestamp"].replace('Z', '+00:00'))
                            elif isinstance(msg["timestamp"], datetime):
                                # Ensure datetime is timezone aware
                                if msg["timestamp"].tzinfo is None:
                                    # If naive, assume it's in UTC
                                    msg_time = msg["timestamp"].replace(tzinfo=timezone.utc)
                                else:
                                    msg_time = msg["timestamp"]
                        except (ValueError, TypeError) as e:
                            print(f"Error parsing timestamp: {e}, timestamp: {msg['timestamp']}")
                            # If we can't parse the timestamp, include the message (assume it's recent)
                            # Only add role and content fields
                            if "role" in msg and "content" in msg:
                                recent_history.append({"role": msg["role"], "content": msg["content"]})
                            continue
                        
                        # Only include messages from the last 2 hours
                        if msg_time and msg_time >= two_hours_ago:
                            # Only add role and content fields
                            if "role" in msg and "content" in msg:
                                recent_history.append({"role": msg["role"], "content": msg["content"]})
                    else:
                        # If no timestamp, include the message (assume it's recent)
                        # Only add role and content fields
                        if "role" in msg and "content" in msg:
                            recent_history.append({"role": msg["role"], "content": msg["content"]})
                
                # Take only the last 30 messages
                limited_history = recent_history[-30:] if len(recent_history) > 30 else recent_history
                
                # Add the filtered and limited history to messages
                api_messages.extend(limited_history)
            else:
                # If no history provided, just add the current message
                api_messages.append({"role": "user", "content": message})
            
            # Debug: Print the number of messages being sent to OpenAI
            print(f"Sending {len(api_messages)} messages to OpenAI")
            
            # For checklist requests, use the simpler model for the acknowledgment message
            # For complex queries without checklist, use the more capable model
            message_model = "gpt-4o-mini-2024-07-18" if needs_checklist else ("gpt-4o-2024-11-20" if query_type == "complex" else "gpt-4o-mini-2024-07-18")
            print(f"Using model for message: {message_model}")
            
            try:
                # Generate the conversational response
                response = self.client.chat.completions.create(
                    model=message_model,
                    messages=api_messages,
                    temperature=0.7,
                )
                
                conversation_response = response.choices[0].message.content
                
                # Print the message with agent name, model, and instruction type
                print("=======================")
                print(f"Message Agent ({message_model}) - {instruction_type}")
                print(conversation_response)
                print("=======================")
                
                # Return the raw conversation response - we'll structure it in the calling code
                return conversation_response
                
            except Exception as e:
                # If we hit a rate limit or quota error, try falling back to GPT-4o-mini
                print(f"Error with {message_model}, falling back to GPT-4o-mini-2024-07-18: {e}")
                try:
                    # Try with the fallback model
                    response = self.client.chat.completions.create(
                        model="gpt-4o-mini-2024-07-18",
                        messages=api_messages,
                        temperature=0.7,
                    )
                    
                    conversation_response = response.choices[0].message.content
                    
                    # Print the message with agent name, model, and instruction type
                    print("=======================")
                    print(f"Message Agent (gpt-4o-mini-2024-07-18) - {instruction_type}")
                    print(conversation_response)
                    print("=======================")
                    
                    # Return the raw conversation response
                    return conversation_response
                    
                except Exception as fallback_error:
                    # If even the fallback fails, provide a hardcoded response
                    print(f"Fallback model also failed: {fallback_error}")
                    fallback_message = self._generate_fallback_response(message, user_full_name)
                    
                    # Print the fallback message with agent name and model
                    print("========================")
                    print("Fallback Agent (gpt-4o-mini-2024-07-18)")
                    print(fallback_message)
                    print("========================")
                    
                    # Return the fallback message
                    return fallback_message
            
        except Exception as e:
            print(f"Error generating AI response: {e}")
            # Provide a fallback response instead of raising an exception
            fallback_message = self._generate_fallback_response(message, user_full_name)
            
            # Print the fallback message with agent name and model
            print("========================")
            print("Fallback Agent (gpt-4o-mini-2024-07-18)")
            print(fallback_message)
            print("========================")
            
            # Return the fallback message
            return fallback_message
    
    async def generate_checklist(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None) -> Optional[Dict[str, Any]]:
        """
        Generate checklist items based on the user's message.
        This method is separate from generate_response and only handles checklist generation.
        
        Returns:
            Optional[Dict[str, Any]]: A dictionary of checklist data, or None if generation fails
        """
        try:
            # Get current date and time
            now = datetime.now()
            current_day = now.strftime("%A")  # Get the day of the week (e.g., Monday, Tuesday)
            current_date = now.strftime("%B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for checklist generation
            checklist_system_message = CHECKLIST_AGENT_INSTRUCTIONS.format(
                current_day=current_day,
                current_date=current_date,
                current_time=current_time
            )
            
            # Create messages for checklist generation
            checklist_messages = [
                {"role": "system", "content": checklist_system_message}
            ]
            
            # Prepare context from message history
            limited_history = []
            if message_history:
                # Filter out system messages from history to avoid conflicts
                filtered_history = [msg for msg in message_history if msg.get("role") != "system"]
                
                # Apply time constraint - only messages from the last 2 hours
                # Use UTC timezone for consistency
                two_hours_ago = datetime.now(timezone.utc) - timedelta(hours=2)
                recent_history = []
                
                for msg in filtered_history:
                    # Check if the message has a timestamp
                    if "timestamp" in msg:
                        msg_time = None
                        # Try to parse the timestamp
                        try:
                            if isinstance(msg["timestamp"], str):
                                # Parse string to datetime with timezone awareness
                                msg_time = datetime.fromisoformat(msg["timestamp"].replace('Z', '+00:00'))
                            elif isinstance(msg["timestamp"], datetime):
                                # Ensure datetime is timezone aware
                                if msg["timestamp"].tzinfo is None:
                                    # If naive, assume it's in UTC
                                    msg_time = msg["timestamp"].replace(tzinfo=timezone.utc)
                                else:
                                    msg_time = msg["timestamp"]
                        except (ValueError, TypeError) as e:
                            print(f"Error parsing timestamp: {e}, timestamp: {msg['timestamp']}")
                            # If we can't parse the timestamp, include the message (assume it's recent)
                            # Only add role and content fields
                            if "role" in msg and "content" in msg:
                                recent_history.append({"role": msg["role"], "content": msg["content"]})
                            continue
                        
                        # Only include messages from the last 2 hours
                        if msg_time and msg_time >= two_hours_ago:
                            # Only add role and content fields
                            if "role" in msg and "content" in msg:
                                recent_history.append({"role": msg["role"], "content": msg["content"]})
                    else:
                        # If no timestamp, include the message (assume it's recent)
                        # Only add role and content fields
                        if "role" in msg and "content" in msg:
                            recent_history.append({"role": msg["role"], "content": msg["content"]})
                
                # Take only the last 30 messages
                limited_history = recent_history[-30:] if len(recent_history) > 30 else recent_history
                
                # Add the filtered and limited history to messages
                checklist_messages.extend(limited_history)
            else:
                # If no history provided, just add the current message
                checklist_messages.append({"role": "user", "content": message})
            
            # Add instructions for the output format
            format_instruction = CHECKLIST_FORMAT_INSTRUCTIONS
            
            # Add the format instruction to the last message
            if checklist_messages[-1]["role"] == "user":
                checklist_messages[-1]["content"] += "\n\n" + format_instruction
            else:
                checklist_messages.append({"role": "user", "content": format_instruction})
            
            # Generate checklist items
            checklist_response = self.client.chat.completions.create(
                model="gpt-4o-2024-11-20",  # Always use the more capable model for checklists
                messages=checklist_messages,
                temperature=0.7,
                response_format={"type": "json_object"}
            )
            
            checklist_content = checklist_response.choices[0].message.content
            
            # Try to parse the checklist JSON
            try:
                checklist_json = json.loads(checklist_content)
                checklist_data = checklist_json.get("checklists", {})
                
                # Print the checklist data with agent name and model
                print("=======================")
                print("Checklist Agent (gpt-4o-2024-11-20)")
                print(json.dumps(checklist_data, indent=2))
                print("========================")
                
                return checklist_data
                
            except json.JSONDecodeError as e:
                print(f"Error parsing checklist JSON: {e}")
                print(f"Raw checklist response: {checklist_content}")
                # Return None if parsing fails
                return None
                
        except Exception as e:
            print(f"Error generating checklist: {e}")
            # Return None on error
            return None
    
    def _generate_fallback_response(self, message: str, user_full_name: Optional[str] = None) -> str:
        """Generate a fallback response when API calls fail"""
        greeting = f"Hi {user_full_name.split()[0] if user_full_name else 'there'}"
        
        if "plan" in message.lower() or "schedule" in message.lower() or "day" in message.lower():
            return f"{greeting}! I'd be happy to help you plan your day. I recommend starting with your thesis work when your energy is highest, then taking a break before going grocery shopping. Would you like me to help you create a more detailed schedule?"
        
        if "remind" in message.lower() or "remember" in message.lower():
            return f"{greeting}! I'll make a note of that for you. Is there a specific time you'd like me to remind you?"
        
        if "help" in message.lower() or "assist" in message.lower():
            return f"{greeting}! I'm here to help you. What specific assistance do you need today?"
        
        # Default fallback response
        return f"{greeting}! I'm here to help you with your tasks and objectives. How can I assist you today?" 