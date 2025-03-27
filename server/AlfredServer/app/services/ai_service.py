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
CHECKLIST_CLASSIFIER_INSTRUCTIONS = """You are a classifier agent who helps determine if a user wants to add items to a digital planner/calendar/checklist.
The current date and time is {current_date} at {current_time}.

Your one job is to answer this question:
Has the conversation made it explicity clear that the user wants to add tasks/reminders to their planner/calendar/checklist?

Respond with ONLY one word: 'yes' or 'no'.
'yes': If the user DEFINITELY wants us to generate planner/calendar/checklist/reminder content.
'no': It is not clear that the user wants us to add items to their planner/calendar/checklist.
"""

# -------------------------------------------------------------------------
# Checklist Inquiry Agent - Determines if more information is needed before generating a checklist
# -------------------------------------------------------------------------
CHECKLIST_INQUIRY_INSTRUCTIONS = """You are an inquiry classifier that determines if we have enough information to create a meaningful checklist.
The current date and time is {current_date} at {current_time}.
We are in the process of updating the user's planner/calendar/checklist.

Based on the context, can we infer the task(s) and on what day(s) the tasks on are?
Respond with ONLY one word: 'more' or 'enough'.

'more':
1. We don't know the day(s) the task(s) are on.
2. We don't know what the task is.
3. The user implies they want feedback on the task.
4. We are uncertain about specific details pertaining to complex tasks or long term plans.
5. They need to be notified of something at a specific yet unspecified time.
'enough': 
1. The user if frustrated with us not creating the task yet.
2. The user has already been asked for more information and assumes the agent will figure it out for them.
3. We can infer the day (and time if its a reminder) and the task.
4. If we've been directed to make a plan for them.
5. The task is simple.

Enough supercedes more.
"""

# -------------------------------------------------------------------------
# Message Agent - Generates conversational responses
# -------------------------------------------------------------------------
MESSAGE_AGENT_BASE_INSTRUCTIONS = """You are Alfred, a personal assistant currently texting {user_full_name}.
The current date and time is {current_date} at {current_time}.
Your ultimate goal is to make the {user_full_name}'s life better in the long term.
Your personality is casual, wise, helpful, somewhat reserved, and practical (similar to Alfred, Batman's butler).
Be concise, remove fluff and redundancy.
You can use one word responses or emojis when appropriate, although you can expand if the situation calls for it.

Although you are capable of setting reminders and tasks, you are a part of the agent that is only active when we have have NOT updated the user's planner/calendar/checklist yet.
This implies that you have not updated anything related to the user's planner/calendar/checklist.
"""

MESSAGE_AGENT_CHECKLIST_INSTRUCTIONS = """
You are in the process of updating the user's planner/calendar/checklist.
Only respond with a brief acknowledgment that you're updating their planner, nothing else.
"""

# -------------------------------------------------------------------------
# Checklist Generation Agent - Creates structured checklist items
# -------------------------------------------------------------------------
CHECKLIST_AGENT_INSTRUCTIONS = """You are a checklist creation specialist.
The current date and time is {current_date} at {current_time}.
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
The current date and time is {current_date} at {current_time}.

The user is requesting a checklist or set of tasks to be added to their planner, but I need more specific information.
Your job is to ask 1-2 BRIEF, FRIENDLY questions to gather the necessary details like:
- Timeframes or deadlines (don't ask for specific times of day unless it's obvious the reminder requires it)

And only if it's absolutely necessary due to how vague it is:
- Specific tasks they want to accomplish
- Any other critical details needed to create a useful checklist

Be conversational but CONCISE (keep your response under 50 words if possible). 
Don't lecture the user or explain why you need more information - just ask for it directly.

You only exist to ask questions and gather information, NEVER make any statements or assertions.
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
                                max_messages: int = 50) -> List[Dict[str, Any]]:
        """
        Standardized method to prepare context messages from history.
        
        The mobile client is responsible for sending at most 50 messages.
        This method will trim to max_messages if needed and clean the messages.
        
        Args:
            message_history: List of message dictionaries (typically provided by the mobile client)
            max_messages: Maximum number of most recent messages to include (default: 50)
            
        Returns:
            List of filtered message dictionaries with only role and content
        """
        # Return empty list if no history provided
        if not message_history:
            return []
            
        # Filter out system messages from history to avoid conflicts
        filtered_history = [msg for msg in message_history if msg.get("role") != "system"]
            
        # Create a clean version of each message with just role and content
        clean_history = []
        for msg in filtered_history:
            if "role" in msg and "content" in msg:
                # Create a clean message with required fields only
                clean_msg = {"role": msg["role"], "content": msg["content"]}
                clean_history.append(clean_msg)
        
        # If we have more messages than max_messages, take the most recent ones
        if len(clean_history) > max_messages:
            clean_history = clean_history[-max_messages:]
            
        return clean_history
        
    async def classify_query(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, now: Optional[datetime] = None) -> str:
        """
        Classify the user's query as either 'simple' or 'complex'
        
        Simple: Standard conversation, greetings, basic questions
        Complex: Reasoning, planning, updating checklists, multi-step tasks
        """
        try:
            print("=== AGENT: Query Classifier ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Use the provided time or default to current time
            if now is None:
                now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for classification with date/time
            classification_prompt = QUERY_CLASSIFIER_INSTRUCTIONS
            
            # Prepare context from message history using the standardized method
            # Limit to only the last 10 messages
            context_messages = self._prepare_context_messages(message_history, max_messages=10)
            
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
            
            print(f"Query classified as: {result}")
            print(f"Raw: {result}")
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
    
    async def should_generate_checklist(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, now: Optional[datetime] = None) -> bool:
        """
        Determine if the response should include checklist items
        
        Returns True if the user's query is related to tasks, todos, or checklists
        """
        try:
            print("=== AGENT: Checklist Classifier ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Get current date and time if needed
            if now is None:
                now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for checklist classification
            classification_prompt = CHECKLIST_CLASSIFIER_INSTRUCTIONS.format(
                current_date=current_date,
                current_time=current_time
            )
            
            # Prepare context from message history using the standardized method
            # Limit to only the last 10 messages
            context_messages = self._prepare_context_messages(message_history, max_messages=10)
            
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

            print("Raw:", result)
            
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
            
    async def should_inquire_further(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, now: Optional[datetime] = None) -> bool:
        """
        Determine if we need to ask for more information before generating a checklist.
        
        Returns True if we need more details from the user, False if we have enough information.
        """
        try:
            print("=== AGENT: Checklist Inquiry Classifier ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Get current date and time
            if now is None:
                now = datetime.now()
            current_day = now.strftime("%A")  # Get day of week (Monday, Tuesday, etc.)
            current_date = now.strftime("%B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for checklist inquiry classification
            inquiry_prompt = CHECKLIST_INQUIRY_INSTRUCTIONS.format(
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
        
    async def generate_inquiry_response(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, user_full_name: Optional[str] = None, now: Optional[datetime] = None) -> str:
        """
        Generate a response asking for more details needed to create a meaningful checklist.
        
        This is used when the checklist_inquiry_agent determines we need more information.
        """
        try:
            print("=== AGENT: Inquiry Response Generator ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Get current date and time
            if now is None:
                now = datetime.now()
            current_day = now.strftime("%A")
            current_date = now.strftime("%B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for generating inquiry responses
            inquiry_system_message = INQUIRY_RESPONSE_INSTRUCTIONS.format(
                user_full_name=user_full_name or 'the user',
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
    
    async def generate_checklist(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, now: Optional[datetime] = None) -> Optional[Dict[str, Any]]:
        """
        Generate checklist items based on the user's message.
        This method is separate from generate_response and only handles checklist generation.
        
        Args:
            message: The user's message
            message_history: Previous message history for context
            now: Current datetime (optional)
            
        Returns:
            Optional[Dict[str, Any]]: A dictionary of checklist data, or None if generation fails
        """
        try:
            print("=== AGENT: Checklist Generator ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Get current date and time
            if now is None:
                now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a specialized system message for checklist generation
            checklist_system_message = CHECKLIST_AGENT_INSTRUCTIONS.format(
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
        
    async def _generate_checklist_acknowledgment(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, user_full_name: Optional[str] = None, now: Optional[datetime] = None) -> str:
        """
        Generate a simple acknowledgment for checklist creation.
        Uses the MESSAGE_AGENT_CHECKLIST_INSTRUCTIONS.
        
        Args:
            message: The user's message
            message_history: Previous message history for context
            user_full_name: The user's full name for personalization
            now: Current datetime (optional)
            
        Returns:
            str: A brief acknowledgment message
        """
        try:
            # Get current date and time
            if now is None:
                now = datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Create a personalized system message with date/time combining both instruction sets
            system_message = MESSAGE_AGENT_CHECKLIST_INSTRUCTIONS
            
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
            print("=== AGENT: Checklist Acknowledgment Generator ===")
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
                                         user_full_name: Optional[str] = None, now: Optional[datetime] = None) -> str:
        """
        Generate a standard response for non-checklist queries based on complexity.
        Uses MESSAGE_AGENT_BASE_INSTRUCTIONS.
        
        Args:
            message: The user's message
            query_type: Classification of the query ('simple' or 'complex')
            message_history: Previous message history for context
            user_full_name: The user's full name for personalization
            now: Current datetime (optional)
            
        Returns:
            str: A response message
        """
        try:
            # Use the provided time or default to current time
            if now is None:
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
                print("=== AGENT: Standard Response Generator ===")
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
                                         user_full_name: Optional[str] = None, user_id: Optional[str] = None,
                                         client_time: Optional[str] = None) -> Dict[str, Any]:
        """
        Optimized response generation that avoids unnecessary API calls.
        Makes decisions in the correct sequence to ensure no wasted API calls.
        
        Args:
            message: The user's message
            message_history: Previous message history for context
            user_full_name: The user's full name for personalization
            user_id: The user's ID
            client_time: The current time on the client device (optional)
            
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
            # Parse client time if provided for more accurate time-based responses
            client_datetime = None
            if client_time:
                try:
                    # Parse ISO 8601 format (2023-09-15T14:30:00Z)
                    client_datetime = datetime.fromisoformat(client_time.replace('Z', '+00:00'))
                    print(f"Using client time: {client_datetime}")
                except (ValueError, TypeError) as e:
                    print(f"Error parsing client time: {e}. Using server time instead.")
            
            # Get current date and time (from client or server)
            now = client_datetime or datetime.now()
            current_date = now.strftime("%A, %B %d, %Y")
            current_time = now.strftime("%I:%M %p")
            
            # Step 1: Check if this is a checklist request
            result['needs_checklist'] = await self.should_generate_checklist(message, message_history, now)
            
            # Step 2: If it's a checklist request, check if we need more information
            if result['needs_checklist']:
                result['needs_more_info'] = await self.should_inquire_further(message, message_history, now)
                
                #Step 2a: If we need more info, generate an inquiry response asking for more details
                if result['needs_more_info']:
                    # Generate an inquiry response asking for more details
                    result['response_text'] = await self.generate_inquiry_response(message, message_history, user_full_name, now)
                
                #Step 2b: If we have enough info, generate an acknowledgment
                else:
                    # It's a checklist and we have enough info, generate acknowledgment
                    # Using the dedicated method with proper instructions
                    result['response_text'] = await self._generate_checklist_acknowledgment(message, message_history, user_full_name, now)
            
            # Step 3: If it's not a checklist request, generate a standard response based on query complexity
            else:
                # Step 3a: First determine query complexity (ALWAYS needed for model selection)...
                #...then generate a standard response based on query complexity
                result['query_type'] = await self.classify_query(message, message_history, now)
                result['response_text'] = await self._generate_standard_response(
                    message, result['query_type'], message_history, user_full_name, now
                )
            
            return result
            
        except Exception as e:
            print(f"Error in generate_optimized_response: {e}")
            # Provide a fallback response
            result['response_text'] = self._generate_fallback_response(message, user_full_name)
            
            # Log the error fallback
            print("=== AGENT: Optimized Response (Error) ===")
            print(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            print(f"Output: \"{result['response_text'][:75]}{'...' if len(result['response_text']) > 75 else ''}\"")
            print(f"Context msgs: 0")
            print(f"Model: hardcoded fallback")
            print("===============================\n")
            
            return result 