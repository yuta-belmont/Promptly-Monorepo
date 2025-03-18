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

# -------------------------------------------------------------------------
# Query Classifier Agent - Determines complexity of processing needed
# -------------------------------------------------------------------------
QUERY_CLASSIFIER_INSTRUCTIONS = """You are a query classifier that determines if a user message requires simple or complex processing.
SIMPLE: Standard conversation, greetings, factual questions, short responses.
COMPLEX: Reasoning, planning, updating checklists, multi-step tasks, detailed explanations.

Respond with ONLY one word: either 'simple' or 'complex'."""

# -------------------------------------------------------------------------
# Checklist Classifier Agent - Determines if a checklist should be generated
# -------------------------------------------------------------------------
CHECKLIST_CLASSIFIER_INSTRUCTIONS = """You are a classifier that determines if a response should include checklist items.
Today is {current_date} and the current time is {current_time}.
Determine if the user's message is requesting or implying the creation of:
- A to-do list or checklist
- Task reminders
- Action items
- Scheduled activities
- Any form of trackable items that should be added to their planner

Respond with ONLY 'yes' if checklist items should be generated, or 'no' if not."""

# -------------------------------------------------------------------------
# Checklist Inquiry Agent - Determines if more information is needed before generating a checklist
# -------------------------------------------------------------------------
CHECKLIST_INQUIRY_INSTRUCTIONS = """You are an inquiry classifier that determines if we have enough information to create a meaningful checklist.
Today is {current_day}, {current_date} and the current time is {current_time}.

Analyze if the user's message, combined with chat history, provides enough specific details to create a good checklist, such as:
- Clear timeframes (dates, days, times)
- Specific tasks to be done
- Enough context from previous messages to infer missing details
- Sufficient clarity about what the user wants to accomplish

We require a clear time frame, specific tasks, and enough context to infer missing details so that we can createa a useful detailed planner.

Respond with ONLY one word:'enough' or 'more'."""

# -------------------------------------------------------------------------
# Message Agent - Generates conversational responses
# -------------------------------------------------------------------------
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

# -------------------------------------------------------------------------
# Checklist Generation Agent - Creates structured checklist items
# -------------------------------------------------------------------------
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

# -------------------------------------------------------------------------
# Inquiry Response Generator - Creates messages asking for more checklist details
# -------------------------------------------------------------------------
INQUIRY_RESPONSE_INSTRUCTIONS = """You are Alfred, a personal assistant currently texting {user_full_name}.
Today is {current_day}, {current_date} and the current time is {current_time}.

The user is requesting a checklist or set of tasks to be added to their planner, but I need more specific information.
Your job is to ask 1-2 BRIEF, FRIENDLY questions to gather the necessary details like:
- Timeframes or deadlines

And only if it's absolutely necessary due to how vague it is:
- Specific tasks they want to accomplish
- Any other critical details needed to create a useful checklist

Be conversational but CONCISE (keep your response under 50 words if possible). 
Don't lecture the user or explain why you need more information - just ask for it directly.
"""

CHECKLIST_FORMAT_INSTRUCTIONS = """Please format your response as a JSON object with the following structure:
{
    "checklists": {
        "YYYY-MM-DD": {
            "notes": "Notes summarizing the day's tasks or null",
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
        
    def _prepare_context_messages(self, message_history: Optional[List[Dict[str, Any]]] = None, 
                                max_messages: int = 30, hours_window: int = 2) -> List[Dict[str, Any]]:
        """
        Standardized method to prepare context messages from history.
        Filters messages to only include those from the last X hours, 
        limited to Y most recent messages.
        
        Args:
            message_history: List of message dictionaries
            max_messages: Maximum number of messages to include
            hours_window: Only include messages from the last X hours
            
        Returns:
            List of filtered message dictionaries with only role and content
        """
        context_messages = []
        
        if not message_history:
            return context_messages
            
        # Filter out system messages from history to avoid conflicts
        filtered_history = [msg for msg in message_history if msg.get("role") != "system"]
        
        # Apply time constraint - only messages from the last X hours
        # Use UTC timezone for consistency
        x_hours_ago = datetime.now(timezone.utc) - timedelta(hours=hours_window)
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
                    # If we can't parse the timestamp, include the message (assume it's recent)
                    # Only add role and content fields
                    if "role" in msg and "content" in msg:
                        recent_history.append({"role": msg["role"], "content": msg["content"]})
                    continue
                
                # Only include messages from the last X hours
                if msg_time and msg_time >= x_hours_ago:
                    # Only add role and content fields
                    if "role" in msg and "content" in msg:
                        recent_history.append({"role": msg["role"], "content": msg["content"]})
            else:
                # If no timestamp, include the message (assume it's recent)
                # Only add role and content fields
                if "role" in msg and "content" in msg:
                    recent_history.append({"role": msg["role"], "content": msg["content"]})
        
        # Take only the last max_messages
        context_messages = recent_history[-max_messages:] if len(recent_history) > max_messages else recent_history
        
        return context_messages
        
    async def classify_query(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None) -> str:
        """
        Classify the user's query as either 'simple' or 'complex'
        
        Simple: Standard conversation, greetings, basic questions
        Complex: Reasoning, planning, updating checklists, multi-step tasks
        """
        try:
            print("\n=== AGENT: Query Classifier ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Get current date and time
            now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for classification with date/time
            classification_prompt = QUERY_CLASSIFIER_INSTRUCTIONS.format(
                current_date=current_date,
                current_time=current_time
            )
            
            # Prepare context from message history using the standardized method
            context_messages = self._prepare_context_messages(message_history)
            
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
                result = "complex"
            else:
                result = "simple"  # Default to 'simple' for any other response
            
            print(f"Output: Query classified as: {result}")
            print(f"Context msgs: {len(context_messages)}")
            print(f"Model: gpt-4o-mini-2024-07-18")
            print("=============================\n")
            
            return result
                
        except Exception as e:
            print(f"Error classifying query: {e}")
            # Default to 'complex' on error to ensure better responses
            print("Output: Defaulting to 'complex' due to error")
            print("=============================\n")
            return "complex"
    
    async def should_generate_checklist(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None) -> bool:
        """
        Determine if the response should include checklist items
        
        Returns True if the user's query is related to tasks, todos, or checklists
        """
        try:
            print("\n=== AGENT: Checklist Classifier ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Get current date and time
            now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for checklist classification
            classification_prompt = CHECKLIST_CLASSIFIER_INSTRUCTIONS.format(
                current_date=current_date,
                current_time=current_time
            )
            
            # Prepare context from message history using the standardized method
            context_messages = self._prepare_context_messages(message_history)
            
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
            
            # Determine the final result
            needs_checklist = 'yes' in result
            
            print(f"Output: Needs checklist: {needs_checklist}")
            print(f"Context msgs: {len(context_messages)}")
            print(f"Model: gpt-4o-mini-2024-07-18")
            print("====================================\n")
            
            # Return True if the result contains 'yes'
            return needs_checklist
                
        except Exception as e:
            print(f"Error classifying for checklist generation: {e}")
            # Default to False on error
            print("Output: Defaulting to FALSE due to error")
            print("====================================\n")
            return False
            
    async def should_inquire_further(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None) -> bool:
        """
        Determine if we need to ask for more information before generating a checklist.
        
        Returns True if we need more details from the user, False if we have enough information.
        """
        try:
            print("\n=== AGENT: Checklist Inquiry Classifier ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Get current date and time
            now = datetime.now()
            current_day = now.strftime("%A")  # Get day of week (Monday, Tuesday, etc.)
            current_date = now.strftime("%B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for checklist inquiry classification
            inquiry_prompt = CHECKLIST_INQUIRY_INSTRUCTIONS.format(
                current_day=current_day,
                current_date=current_date,
                current_time=current_time
            )
            
            # Prepare context from message history using the standardized method
            context_messages = self._prepare_context_messages(message_history)
            
            # Create messages array for classification
            inquiry_messages = [
                {"role": "system", "content": inquiry_prompt}
            ]
            
            # Add context messages if available
            if context_messages:
                inquiry_messages.extend(context_messages)
            
            # Add the current message
            inquiry_messages.append({"role": "user", "content": message})
            
            # Use GPT-4o-mini for inquiry classification
            response = self.client.chat.completions.create(
                model="gpt-4o-mini-2024-07-18",
                messages=inquiry_messages,
                temperature=0.3,  # Lower temperature for more consistent classification
                max_tokens=15  # We only need a short response
            )
            
            # Get the classification result
            result = response.choices[0].message.content.strip().lower()
            
            # Determine the final result
            needs_more_info = 'more' in result
            
            print(f"Output: Needs more information: {needs_more_info}")
            print(f"Context msgs: {len(context_messages)}")
            print(f"Model: gpt-4o-mini-2024-07-18")
            print("===========================================\n")
            
            # Return True if the result contains 'insufficient'
            return needs_more_info
                
        except Exception as e:
            print(f"Error in checklist inquiry classification: {e}")
            # Default to True on error (safer to ask for more info than to generate a bad checklist)
            print("Output: Defaulting to TRUE due to error")
            print("===========================================\n")
            return True
        
    async def generate_inquiry_response(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, user_full_name: Optional[str] = None) -> str:
        """
        Generate a response asking for more details needed to create a meaningful checklist.
        
        This is used when the checklist_inquiry_agent determines we need more information.
        """
        try:
            print("\n=== AGENT: Inquiry Response Generator ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Get current date and time
            now = datetime.now()
            current_day = now.strftime("%A")
            current_date = now.strftime("%B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for generating inquiry responses
            inquiry_system_message = INQUIRY_RESPONSE_INSTRUCTIONS.format(
                user_full_name=user_full_name or 'the user',
                current_day=current_day,
                current_date=current_date,
                current_time=current_time
            )
            
            # Prepare context from message history using the standardized method
            context_messages = self._prepare_context_messages(message_history)
            
            # Create messages array for generating inquiry
            inquiry_messages = [
                {"role": "system", "content": inquiry_system_message}
            ]
            
            # Add context messages if available
            if context_messages:
                inquiry_messages.extend(context_messages)
            
            # Add the current message
            inquiry_messages.append({"role": "user", "content": message})
            
            # Generate the inquiry response using GPT-4o-mini for speed
            response = self.client.chat.completions.create(
                model="gpt-4o-mini-2024-07-18",
                messages=inquiry_messages,
                temperature=0.7,
                max_tokens=100  # Keep responses short
            )
            
            inquiry_response = response.choices[0].message.content
            
            print(f"Output: \"{inquiry_response[:75]}{'...' if len(inquiry_response) > 75 else ''}\"")
            print(f"Context msgs: {len(context_messages)}")
            print(f"Model: gpt-4o-mini-2024-07-18")
            print("========================================\n")
            
            return inquiry_response
                
        except Exception as e:
            print(f"Error generating inquiry response: {e}")
            # Provide a fallback response
            fallback = f"I'd be happy to help with that. Could you provide a bit more detail about what specific tasks you'd like me to track and any relevant timeframes?"
            print(f"Output: Using fallback response due to error")
            print("========================================\n")
            return fallback
        
    async def generate_response(self, message: str, user_id: Optional[str] = None, message_history: Optional[List[Dict[str, Any]]] = None, user_full_name: Optional[str] = None) -> str:
        """
        Generate an AI response to the user's message, optionally using message history for context.
        This method only handles the conversational response, not checklist generation.
        """
        try:
            print("\n=== AGENT: Message Generator ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # First, classify the query
            query_type = await self.classify_query(message, message_history)
            
            # Determine if we should generate checklist items
            needs_checklist = await self.should_generate_checklist(message, message_history)
            
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
            
            # Prepare context from message history using the standardized method
            context_messages = self._prepare_context_messages(message_history)
            
            # Add context messages if available
            if context_messages:
                api_messages.extend(context_messages)
            else:
                # If no history provided, just add the current message
                api_messages.append({"role": "user", "content": message})
            
            # For checklist requests, use the simpler model for the acknowledgment message
            # For complex queries without checklist, use the more capable model
            message_model = "gpt-4o-mini-2024-07-18" if needs_checklist else ("gpt-4o-2024-11-20" if query_type == "complex" else "gpt-4o-mini-2024-07-18")
            
            try:
                # Generate the conversational response
                response = self.client.chat.completions.create(
                    model=message_model,
                    messages=api_messages,
                    temperature=0.7,
                )
                
                conversation_response = response.choices[0].message.content
                
                print(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                print(f"Context msgs: {len(context_messages)}")
                print(f"Model: {message_model}")
                print("===============================\n")
                
                # Return the raw conversation response - we'll structure it in the calling code
                return conversation_response
                
            except Exception as e:
                # If we hit a rate limit or quota error, try falling back to GPT-4o-mini
                print(f"Error with {message_model}, falling back to gpt-4o-mini-2024-07-18: {e}")
                try:
                    # Try with the fallback model
                    response = self.client.chat.completions.create(
                        model="gpt-4o-mini-2024-07-18",
                        messages=api_messages,
                        temperature=0.7,
                    )
                    
                    conversation_response = response.choices[0].message.content
                    
                    print(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                    print(f"Context msgs: {len(context_messages)}")
                    print(f"Model: gpt-4o-mini-2024-07-18 (fallback)")
                    print("===============================\n")
                    
                    # Return the raw conversation response
                    return conversation_response
                    
                except Exception as fallback_error:
                    # If even the fallback fails, provide a hardcoded response
                    print(f"Fallback model also failed: {fallback_error}")
                    fallback_message = self._generate_fallback_response(message, user_full_name)
                    
                    print(f"Output: \"{fallback_message[:75]}{'...' if len(fallback_message) > 75 else ''}\"")
                    print(f"Context msgs: {len(context_messages)}")
                    print(f"Model: hardcoded fallback")
                    print("===============================\n")
                    
                    # Return the fallback message
                    return fallback_message
            
        except Exception as e:
            print(f"Error generating AI response: {e}")
            # Provide a fallback response instead of raising an exception
            fallback_message = self._generate_fallback_response(message, user_full_name)
            
            print(f"Output: \"{fallback_message[:75]}{'...' if len(fallback_message) > 75 else ''}\"")
            print(f"Context msgs: 0")
            print(f"Model: hardcoded fallback")
            print("===============================\n")
            
            # Return the fallback message
            return fallback_message
    
    async def generate_response_with_classification(self, message: str, user_id: Optional[str] = None, 
                                                   message_history: Optional[List[Dict[str, Any]]] = None, 
                                                   user_full_name: Optional[str] = None) -> Tuple[str, bool]:
        """
        Generate an AI response and return the checklist classification result together.
        This method avoids duplicate classification calls and returns both values.
        
        Returns:
            Tuple[str, bool]: (response_text, needs_checklist)
        """
        try:
            # Note: We're no longer logging at the start - we'll log everything at the end
            
            # First, classify the query
            query_type = await self.classify_query(message, message_history)
            
            # Determine if we should generate checklist items
            # This classification will be returned along with the response
            needs_checklist = await self.should_generate_checklist(message, message_history)
            
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
            
            # Prepare context from message history using the standardized method
            context_messages = self._prepare_context_messages(message_history)
            
            # Add context messages if available
            if context_messages:
                api_messages.extend(context_messages)
            else:
                # If no history provided, just add the current message
                api_messages.append({"role": "user", "content": message})
            
            # For checklist requests, use the simpler model for the acknowledgment message
            # For complex queries without checklist, use the more capable model
            message_model = "gpt-4o-mini-2024-07-18" if needs_checklist else ("gpt-4o-2024-11-20" if query_type == "complex" else "gpt-4o-mini-2024-07-18")
            
            try:
                # Generate the conversational response
                response = self.client.chat.completions.create(
                    model=message_model,
                    messages=api_messages,
                    temperature=0.7,
                )
                
                conversation_response = response.choices[0].message.content
                
                # Only log after we have the final response
                print("\n=== AGENT: Message Generator ===")
                print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
                print(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                print(f"Context msgs: {len(context_messages)}")
                print(f"Model: {message_model}")
                print("===============================\n")
                
                # Return both the response and the classification result
                return conversation_response, needs_checklist
                
            except Exception as e:
                # If we hit a rate limit or quota error, try falling back to GPT-4o-mini
                print(f"Error with {message_model}, falling back to gpt-4o-mini-2024-07-18: {e}")
                try:
                    # Try with the fallback model
                    response = self.client.chat.completions.create(
                        model="gpt-4o-mini-2024-07-18",
                        messages=api_messages,
                        temperature=0.7,
                    )
                    
                    conversation_response = response.choices[0].message.content
                    
                    # Only log after we have the final response
                    print("\n=== AGENT: Message Generator ===")
                    print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
                    print(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                    print(f"Context msgs: {len(context_messages)}")
                    print(f"Model: gpt-4o-mini-2024-07-18 (fallback)")
                    print("===============================\n")
                    
                    # Return both the response and the classification result
                    return conversation_response, needs_checklist
                    
                except Exception as fallback_error:
                    # If even the fallback fails, provide a hardcoded response
                    print(f"Fallback model also failed: {fallback_error}")
                    fallback_message = self._generate_fallback_response(message, user_full_name)
                    
                    # Only log after we have the final fallback response
                    print("\n=== AGENT: Message Generator ===")
                    print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
                    print(f"Output: \"{fallback_message[:75]}{'...' if len(fallback_message) > 75 else ''}\"")
                    print(f"Context msgs: {len(context_messages)}")
                    print(f"Model: hardcoded fallback")
                    print("===============================\n")
                    
                    # Return both the fallback message and the classification result
                    return fallback_message, needs_checklist
            
        except Exception as e:
            print(f"Error generating AI response with classification: {e}")
            # Provide a fallback response instead of raising an exception
            fallback_message = self._generate_fallback_response(message, user_full_name)
            
            # Only log after we have the final fallback response
            print("\n=== AGENT: Message Generator ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            print(f"Output: \"{fallback_message[:75]}{'...' if len(fallback_message) > 75 else ''}\"")
            print(f"Context msgs: 0")
            print(f"Model: hardcoded fallback")
            print("===============================\n")
            
            # Return the fallback message and default classification (False)
            return fallback_message, False
    
    async def generate_checklist(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None) -> Optional[Dict[str, Any]]:
        """
        Generate checklist items based on the user's message.
        This method is separate from generate_response and only handles checklist generation.
        
        Returns:
            Optional[Dict[str, Any]]: A dictionary of checklist data, or None if generation fails
        """
        try:
            print("\n=== AGENT: Checklist Generator ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
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
            
            # Prepare context from message history using the standardized method
            context_messages = self._prepare_context_messages(message_history)
            
            # Add context messages if available
            if context_messages:
                checklist_messages.extend(context_messages)
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
                
                # Log a sample of the checklist data
                data_preview = json.dumps(checklist_data, indent=2)[:200] + "..." if len(json.dumps(checklist_data, indent=2)) > 200 else json.dumps(checklist_data, indent=2)
                print(f"Output: Generated checklist with {len(checklist_data)} date(s)")
                print(f"Context msgs: {len(context_messages)}")
                print(f"Model: gpt-4o-2024-11-20")
                print("====================================\n")
                
                return checklist_data
                
            except json.JSONDecodeError as e:
                print(f"Error parsing checklist JSON: {e}")
                print(f"Output: Failed to parse JSON response")
                print(f"Context msgs: {len(context_messages)}")
                print(f"Model: gpt-4o-2024-11-20")
                print("====================================\n")
                # Return None if parsing fails
                return None
                
        except Exception as e:
            print(f"Error generating checklist: {e}")
            print(f"Output: Failed to generate checklist due to exception")
            print(f"Context msgs: 0")
            print(f"Model: failed call")
            print("====================================\n")
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
        
    async def _generate_checklist_acknowledgment(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, user_full_name: Optional[str] = None) -> str:
        """
        Generate a simple acknowledgment for checklist creation.
        Uses the MESSAGE_AGENT_BASE_INSTRUCTIONS + MESSAGE_AGENT_CHECKLIST_INSTRUCTIONS.
        
        Args:
            message: The user's message
            message_history: Previous message history for context
            user_full_name: The user's full name for personalization
            
        Returns:
            str: A brief acknowledgment message
        """
        try:
            # Get current date and time
            now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a personalized system message with date/time combining both instruction sets
            system_message = MESSAGE_AGENT_BASE_INSTRUCTIONS.format(
                user_full_name=user_full_name or 'the user',
                current_date=current_date,
                current_time=current_time
            ) + MESSAGE_AGENT_CHECKLIST_INSTRUCTIONS
            
            # Create messages array
            api_messages = [
                {"role": "system", "content": system_message}
            ]
            
            # Prepare context from message history
            context_messages = self._prepare_context_messages(message_history)
            
            # Add context messages if available
            if context_messages:
                api_messages.extend(context_messages)
            
            # Add the current message
            api_messages.append({"role": "user", "content": message})
            
            # Always use mini model for checklist acknowledgments
            response = self.client.chat.completions.create(
                model="gpt-4o-mini-2024-07-18",
                messages=api_messages,
                temperature=0.7,
            )
            
            acknowledgment = response.choices[0].message.content
            
            # Log the response
            print("\n=== AGENT: Checklist Acknowledgment Generator ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            print(f"Output: \"{acknowledgment[:75]}{'...' if len(acknowledgment) > 75 else ''}\"")
            print(f"Context msgs: {len(context_messages)}")
            print(f"Model: gpt-4o-mini-2024-07-18")
            print("=======================================\n")
            
            return acknowledgment
            
        except Exception as e:
            print(f"Error generating checklist acknowledgment: {e}")
            # Return a simple hardcoded acknowledgment
            greeting = f"{user_full_name.split()[0] if user_full_name else 'there'}"
            fallback = f"I'll update your planner with those items."
            
            # Log the fallback
            print(f"Output: Using fallback acknowledgment: \"{fallback}\"")
            print("=======================================\n")
            
            return fallback
    
    async def _generate_standard_response(self, message: str, query_type: str, 
                                         message_history: Optional[List[Dict[str, Any]]] = None,
                                         user_full_name: Optional[str] = None) -> str:
        """
        Generate a standard response for non-checklist queries based on complexity.
        Uses MESSAGE_AGENT_BASE_INSTRUCTIONS.
        
        Args:
            message: The user's message
            query_type: Classification of the query ('simple' or 'complex')
            message_history: Previous message history for context
            user_full_name: The user's full name for personalization
            
        Returns:
            str: A response message
        """
        try:
            # Get current date and time
            now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a personalized system message with date/time
            system_message = MESSAGE_AGENT_BASE_INSTRUCTIONS.format(
                user_full_name=user_full_name or 'the user',
                current_date=current_date,
                current_time=current_time
            )
            
            # Create messages array
            api_messages = [
                {"role": "system", "content": system_message}
            ]
            
            # Prepare context from message history
            context_messages = self._prepare_context_messages(message_history)
            
            # Add context messages if available
            if context_messages:
                api_messages.extend(context_messages)
            else:
                # If no history provided, just add the current message
                api_messages.append({"role": "user", "content": message})
            
            # Choose model based on query complexity
            message_model = "gpt-4o-2024-11-20" if query_type == "complex" else "gpt-4o-mini-2024-07-18"
            
            try:
                # Generate response
                response = self.client.chat.completions.create(
                    model=message_model,
                    messages=api_messages,
                    temperature=0.7,
                )
                
                conversation_response = response.choices[0].message.content
                
                # Log the response
                print("\n=== AGENT: Standard Response Generator ===")
                print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
                print(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                print(f"Context msgs: {len(context_messages)}")
                print(f"Model: {message_model}")
                print("===============================\n")
                
                return conversation_response
                
            except Exception as e:
                # If we hit a rate limit or quota error, try falling back to GPT-4o-mini
                print(f"Error with {message_model}, falling back to gpt-4o-mini-2024-07-18: {e}")
                try:
                    # Try with the fallback model
                    response = self.client.chat.completions.create(
                        model="gpt-4o-mini-2024-07-18",
                        messages=api_messages,
                        temperature=0.7,
                    )
                    
                    conversation_response = response.choices[0].message.content
                    
                    print(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                    print(f"Context msgs: {len(context_messages)}")
                    print(f"Model: gpt-4o-mini-2024-07-18 (fallback)")
                    print("===============================\n")
                    
                    return conversation_response
                    
                except Exception as fallback_error:
                    # If even the fallback fails, provide a hardcoded response
                    print(f"Fallback model also failed: {fallback_error}")
                    fallback_message = self._generate_fallback_response(message, user_full_name)
                    
                    print(f"Output: \"{fallback_message[:75]}{'...' if len(fallback_message) > 75 else ''}\"")
                    print(f"Context msgs: {len(context_messages)}")
                    print(f"Model: hardcoded fallback")
                    print("===============================\n")
                    
                    return fallback_message
        except Exception as e:
            print(f"Error in _generate_standard_response: {e}")
            # Provide a fallback response
            fallback_message = self._generate_fallback_response(message, user_full_name)
            
            print(f"Output: \"{fallback_message[:75]}{'...' if len(fallback_message) > 75 else ''}\"")
            print(f"Context msgs: 0")
            print(f"Model: hardcoded fallback (error)")
            print("===============================\n")
            
            return fallback_message
    
    async def generate_optimized_response(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, 
                                         user_full_name: Optional[str] = None, user_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Optimized response generation that avoids unnecessary API calls.
        Makes decisions in the correct sequence to ensure no wasted API calls.
        
        Args:
            message: The user's message
            message_history: Previous message history for context
            user_full_name: The user's full name for personalization
            user_id: The user's ID
            
        Returns:
            Dict[str, Any]: A dictionary containing:
                - 'response_text': The text response to send to the user
                - 'needs_checklist': Whether a checklist is needed
                - 'needs_more_info': Whether more information is needed before generating a checklist
                - 'query_type': Classification of the query (simple/complex)
        """
        result = {
            'response_text': '',
            'needs_checklist': False,
            'needs_more_info': False,
            'query_type': 'simple'
        }
        
        try:
            # Step 1: First determine query complexity (ALWAYS needed for model selection)
            result['query_type'] = await self.classify_query(message, message_history)
            
            # Step 2: Check if this is a checklist request
            result['needs_checklist'] = await self.should_generate_checklist(message, message_history)
            
            # Step 3: If it's a checklist request, check if we need more information
            if result['needs_checklist']:
                result['needs_more_info'] = await self.should_inquire_further(message, message_history)
                
                if result['needs_more_info']:
                    # Generate an inquiry response asking for more details
                    result['response_text'] = await self.generate_inquiry_response(message, message_history, user_full_name)
                else:
                    # It's a checklist and we have enough info, generate acknowledgment
                    # Using the dedicated method with proper instructions
                    result['response_text'] = await self._generate_checklist_acknowledgment(message, message_history, user_full_name)
            else:
                # Not a checklist request, generate standard response based on query complexity
                result['response_text'] = await self._generate_standard_response(
                    message, result['query_type'], message_history, user_full_name
                )
            
            return result
            
        except Exception as e:
            print(f"Error in generate_optimized_response: {e}")
            # Provide a fallback response
            result['response_text'] = self._generate_fallback_response(message, user_full_name)
            
            # Log the error fallback
            print("\n=== AGENT: Optimized Response (Error) ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            print(f"Output: \"{result['response_text'][:75]}{'...' if len(result['response_text']) > 75 else ''}\"")
            print(f"Context msgs: 0")
            print(f"Model: hardcoded fallback")
            print("===============================\n")
            
            return result 