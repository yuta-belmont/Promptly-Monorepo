import os
import re
import json
from typing import Optional, List, Dict, Any, Tuple, Union
from openai import OpenAI
from datetime import datetime, timedelta, timezone
from pydantic import BaseModel
import logging
import uuid

# Set up logging
logger = logging.getLogger(__name__)

class LogBuffer:
    def __init__(self):
        self.buffer = []
        self.current_section = None
        self.request_id = None
        
    def start_request(self, request_id: str):
        self.request_id = request_id
        self.buffer.append(f"\n=== REQUEST {request_id} ===")
        
    def start_section(self, section_name: str):
        self.current_section = section_name
        self.buffer.append(f"=== AGENT: {section_name} ===")
        
    def add(self, message: str):
        if self.current_section:
            self.buffer.append(message)
            
    def end_section(self):
        if self.current_section:
            self.buffer.append("=" * len(f"=== AGENT: {self.current_section} ==="))
            self.current_section = None
            
    def end_request(self):
        if self.request_id:
            self.buffer.append(f"=== END REQUEST {self.request_id} ===\n")
            self.flush()
            self.request_id = None
            
    def flush(self):
        if self.buffer:
            for line in self.buffer:
                logger.info(line)
            self.buffer = []
            
    def clear(self):
        self.buffer = []
        self.current_section = None
        self.request_id = None

# Create a global log buffer instance
log_buffer = LogBuffer()

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
CHECKLIST_CLASSIFIER_INSTRUCTIONS = """
You are a chat classifier inside a planner application that determines if a user wants to create a plan, task, reminder, or checklist of any kind.
Answer the following based on the user's most recent message:
YES: the user wants to add tasks, reminders, or plans to their planner.
NO: the user does not want to add tasks, reminders, or plans to their planner.
Respond with ONLY ONE word: either ‘yes’, or ‘no’
"""

# -------------------------------------------------------------------------
# Checklist Inquiry Agent - Determines if more information is needed before generating a checklist
# -------------------------------------------------------------------------
CHECKLIST_INQUIRY_INSTRUCTIONS = """You are an inquiry classifier that determines if we have enough information to create a meaningful checklist.
The current date and time is {current_date} at {current_time}.
We are in the process of updating the user's planner/calendar/checklist but we need to know when and what they want to add.

Based on the context, can we infer the task(s) and on what day(s) the tasks on are?
Respond with ONLY one word: 'more' or 'enough'.
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
    "checklist_data": {
        "group1": {
            "name": "Optional group name or null",
            "dates": {
                "YYYY-MM-DD": {
                    "notes": "Optional notes for this date or null",
                    "items": [
                        {
                            "title": "Task description",
                            "notification": "HH:MM or null",
                            "subitems": [
                                {
                                    "title": "Subtask description"
                                }
                            ]
                        }
                    ]
                }
            }
        }
    }
}

Groups can have any name as their key. Each group can contain multiple dates."""

# Pydantic models for structured responses
class ChecklistSubItem(BaseModel):
    title: str

class ChecklistItem(BaseModel):
    title: str
    notification: Optional[str]
    subitems: Optional[List[ChecklistSubItem]] = []

class ChecklistDate(BaseModel):
    notes: Optional[str]
    items: List[ChecklistItem]

class ChecklistGroup(BaseModel):
    name: Optional[str]
    dates: Dict[str, ChecklistDate]

class AlfredResponse(BaseModel):
    message: str
    checklist_data: Optional[Dict[str, ChecklistGroup]]

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
            log_buffer.start_section("Query Classifier")
            log_buffer.add(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
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
            
            log_buffer.add(f"Query classified as: {result}")
            log_buffer.add(f"Raw: {result}")
            log_buffer.add(f"Context msgs: {len(context_messages)}")
            log_buffer.add(f"Model: gpt-4o-mini-2024-07-18")
            log_buffer.end_section()
            log_buffer.flush()
            
            return result
                
        except Exception as e:
            logger.error(f"Error classifying query: {e}")
            # Default to 'complex' on error to ensure better responses
            log_buffer.add("Output: Defaulting to 'complex' due to error")
            log_buffer.end_section()
            log_buffer.flush()
            return "complex"
    
    async def should_generate_checklist(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, now: Optional[datetime] = None) -> bool:
        """
        Determine if the response should include checklist items
        
        Returns True if the user's query is related to tasks, todos, or checklists
        """
        try:
            log_buffer.start_section("Checklist Classifier")
            log_buffer.add(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
            # Create a specialized system message for checklist classification
            classification_prompt = CHECKLIST_CLASSIFIER_INSTRUCTIONS
            
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

            # Use GPT-4o-mini for classification - faster and still accurate for this task
            response = self.client.chat.completions.create(
                model="gpt-4o-mini-2024-07-18",  # Updated model name
                messages=classification_messages,
                temperature=0.3,  # Lower temperature for more consistent classification
                max_tokens=1  # We only need a single word response
            )
            
            # Get the classification result
            result = response.choices[0].message.content.strip().lower()
            
            # Determine the final result
            needs_checklist = 'yes' in result

            log_buffer.add(f"Raw: {result}")
            log_buffer.add(f"Output: Needs checklist: {needs_checklist}")
            log_buffer.add(f"Context msgs: {len(context_messages)}")
            log_buffer.add(f"Model: gpt-4o-mini-2024-07-18")
            log_buffer.end_section()
            log_buffer.flush()
            
            return needs_checklist
                
        except Exception as e:
            logger.error(f"Error classifying for checklist generation: {e}")
            # Default to False on error
            log_buffer.add("Output: Defaulting to FALSE due to error")
            log_buffer.end_section()
            log_buffer.flush()
            return False
            
    async def should_inquire_further(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, now: Optional[datetime] = None) -> bool:
        """
        Determine if we need to ask for more information before generating a checklist.
        
        Returns True if we need more details from the user, False if we have enough information.
        """
        try:
            logger.info("=== AGENT: Checklist Inquiry Classifier ===")
            logger.info(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
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
            
            logger.info(f"Output: Needs more information: {needs_more_info}")
            logger.debug(f"Context msgs: {len(context_messages)}")
            logger.debug(f"Model: gpt-4o-mini-2024-07-18")
            logger.info("===========================================")
            
            # Return True if the result contains 'insufficient'
            return needs_more_info
                
        except Exception as e:
            logger.error(f"Error in checklist inquiry classification: {e}")
            # Default to True on error (safer to ask for more info than to generate a bad checklist)
            logger.info("Output: Defaulting to TRUE due to error")
            logger.info("===========================================")
            return True
        
    async def generate_inquiry_response(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, user_full_name: Optional[str] = None, now: Optional[datetime] = None) -> str:
        """
        Generate a response asking for more details needed to create a meaningful checklist.
        
        This is used when the checklist_inquiry_agent determines we need more information.
        """
        try:
            logger.info("=== AGENT: Inquiry Response Generator ===")
            logger.info(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
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
            
            logger.info(f"Output: \"{inquiry_response[:75]}{'...' if len(inquiry_response) > 75 else ''}\"")
            logger.debug(f"Context msgs: {len(context_messages)}")
            logger.debug(f"Model: gpt-4o-mini-2024-07-18")
            logger.info("========================================")
            
            return inquiry_response
                
        except Exception as e:
            logger.error(f"Error generating inquiry response: {e}")
            # Provide a fallback response
            fallback = f"I'd be happy to help with that. Could you provide a bit more detail about what specific tasks you'd like me to track and any relevant timeframes?"
            logger.info(f"Output: Using fallback response due to error")
            logger.info("========================================")
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
            logger.info("=== AGENT: Checklist Generator ===")
            logger.info(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            
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
                checklist_data = checklist_json.get("checklist_data", {})
                
                # Log a sample of the checklist data
                data_preview = json.dumps(checklist_data, indent=2)[:200] + "..." if len(json.dumps(checklist_data, indent=2)) > 200 else json.dumps(checklist_data, indent=2)
                logger.info(f"Output: Generated checklist with {len(checklist_data)} date(s)")
                logger.debug(f"Context msgs: {len(context_messages)}")
                logger.debug(f"Model: gpt-4o-2024-11-20")
                logger.info("=====================================")
                
                return checklist_data
                
            except json.JSONDecodeError as e:
                logger.error(f"Error parsing checklist JSON: {e}")
                logger.info(f"Output: Failed to parse JSON response")
                logger.debug(f"Context msgs: {len(context_messages)}")
                logger.debug(f"Model: gpt-4o-2024-11-20")
                logger.info("=====================================")
                # Return None if parsing fails
                return None
                
        except Exception as e:
            logger.error(f"Error generating checklist: {e}")
            logger.info(f"Output: Failed to generate checklist due to exception")
            logger.debug(f"Context msgs: 0")
            logger.debug(f"Model: failed call")
            logger.info("=====================================")
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
            logger.info("=== AGENT: Checklist Acknowledgment Generator ===")
            logger.info(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            logger.info(f"Output: \"{acknowledgment[:75]}{'...' if len(acknowledgment) > 75 else ''}\"")
            logger.debug(f"Context msgs: {len(context_messages)}")
            logger.debug(f"Model: gpt-4o-mini-2024-07-18")
            logger.info("=======================================")
            
            return acknowledgment
            
        except Exception as e:
            logger.error(f"Error generating checklist acknowledgment: {e}")
            # Return a simple hardcoded acknowledgment
            greeting = f"{user_full_name.split()[0] if user_full_name else 'there'}"
            fallback = f"I'll update your planner with those items."
            
            # Log the fallback
            logger.info(f"Output: Using fallback acknowledgment: \"{fallback}\"")
            logger.info("=======================================")
            
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
                logger.info("=== AGENT: Standard Response Generator ===")
                logger.info(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
                logger.info(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                logger.debug(f"Context msgs: {len(context_messages)}")
                logger.debug(f"Model: {message_model}")
                logger.info("===============================")
                
                return conversation_response
                
            except Exception as e:
                # If we hit a rate limit or quota error, try falling back to GPT-4o-mini
                logger.info(f"Error with {message_model}, falling back to gpt-4o-mini-2024-07-18: {e}")
                try:
                    # Try with the fallback model
                    response = self.client.chat.completions.create(
                        model="gpt-4o-mini-2024-07-18",
                        messages=api_messages,
                        temperature=0.7,
                    )
                    
                    conversation_response = response.choices[0].message.content
                    
                    logger.info(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                    logger.debug(f"Context msgs: {len(context_messages)}")
                    logger.debug(f"Model: gpt-4o-mini-2024-07-18 (fallback)")
                    logger.info("===============================")
                    
                    return conversation_response
                    
                except Exception as fallback_error:
                    # If even the fallback fails, provide a hardcoded response
                    logger.error(f"Fallback model also failed: {fallback_error}")
                    fallback_message = self._generate_fallback_response(message, user_full_name)
                    
                    logger.info(f"Output: \"{fallback_message[:75]}{'...' if len(fallback_message) > 75 else ''}\"")
                    logger.debug(f"Context msgs: {len(context_messages)}")
                    logger.debug(f"Model: hardcoded fallback")
                    logger.info("===============================")
                    
                    return fallback_message
        except Exception as e:
            logger.error(f"Error in _generate_standard_response: {e}")
            # Provide a fallback response
            fallback_message = self._generate_fallback_response(message, user_full_name)
            
            logger.info(f"Output: \"{fallback_message[:75]}{'...' if len(fallback_message) > 75 else ''}\"")
            logger.debug(f"Context msgs: 0")
            logger.debug(f"Model: hardcoded fallback (error)")
            logger.info("===============================")
            
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
            # Generate a unique request ID for this interaction
            request_id = str(uuid.uuid4())[:8]
            log_buffer.start_request(request_id)
            
            # Parse client time if provided for more accurate time-based responses
            client_datetime = None
            if client_time:
                try:
                    # Parse ISO 8601 format (2023-09-15T14:30:00Z)
                    client_datetime = datetime.fromisoformat(client_time.replace('Z', '+00:00'))
                    log_buffer.add(f"Using client time: {client_datetime}")
                except (ValueError, TypeError) as e:
                    log_buffer.add(f"Error parsing client time: {e}. Using server time instead.")
            
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
            
            # End the request and flush all logs
            log_buffer.end_request()
            return result
            
        except Exception as e:
            logger.error(f"Error in generate_optimized_response: {e}")
            # Provide a fallback response
            result['response_text'] = self._generate_fallback_response(message, user_full_name)
            
            # Log the error fallback
            log_buffer.add("=== AGENT: Optimized Response (Error) ===")
            log_buffer.add(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            log_buffer.add(f"Output: \"{result['response_text'][:75]}{'...' if len(result['response_text']) > 75 else ''}\"")
            log_buffer.add(f"Context msgs: 0")
            log_buffer.add(f"Model: hardcoded fallback")
            log_buffer.add("===============================")
            
            # End the request and flush all logs
            log_buffer.end_request()
            return result 

    def convertFirebaseChecklistToModel(self, checklistData: Dict[str, Any]) -> Optional[List[Dict[str, Any]]]:
        logger.info("CHECKLIST DEBUG: Converting Firebase checklist data to model: %s", checklistData)
        
        # Verify we have data to process
        if not checklistData:
            logger.warning("CHECKLIST DEBUG: Empty checklist data received")
            return None
        
        # Create an array to hold all checklists
        allChecklists: List[Dict[str, Any]] = []
        dateFormatter = datetime.strptime("%Y-%m-%d", "%Y-%m-%d")
        
        # Process each group in the checklist data
        for groupKey, groupData in checklistData.items():
            logger.debug("CHECKLIST DEBUG: Processing group: %s", groupKey)
            
            # Get the group name if available
            groupName = groupData.get("name")
            group = {"name": groupName, "dates": {}} if groupName and groupName.strip() != "" else None
            
            # Process dates within the group
            if "dates" in groupData:
                for dateString, dateData in groupData["dates"].items():
                    # Skip any keys that aren't date strings
                    if not re.match(r"^\d{4}-\d{2}-\d{2}$", dateString):
                        logger.debug("CHECKLIST DEBUG: Skipping non-date key: %s", dateString)
                        continue
                    
                    # Parse the date
                    try:
                        date = dateFormatter.parse(dateString)
                    except ValueError:
                        logger.warning("CHECKLIST DEBUG: Failed to parse date: %s", dateString)
                        continue
                    
                    # Get the notes from the checklist
                    notes = dateData.get("notes", "")
                    
                    # Parse the items array
                    checklistItems: List[Dict[str, Any]] = []
                    if "items" in dateData:
                        for itemData in dateData["items"]:
                            if "title" in itemData:
                                # Parse notification time if present
                                notificationDate = None
                                if "notification" in itemData and itemData["notification"] != "null":
                                    logger.debug("CHECKLIST DEBUG: Processing notification time: %s", itemData["notification"])
                                    # Combine the date with the time
                                    timeFormatter = datetime.strptime("%I:%M %p", "%I:%M %p")
                                    try:
                                        time = timeFormatter.parse(itemData["notification"])
                                        notificationDate = date.replace(hour=time.hour, minute=time.minute, second=0)
                                        
                                        logger.debug("CHECKLIST DEBUG: Parsed time %s to components - hour: %d, minute: %d", 
                                                    itemData["notification"], time.hour, time.minute)
                                        logger.debug("CHECKLIST DEBUG: Created notification date: %s", notificationDate)
                                    except ValueError:
                                        logger.warning("CHECKLIST DEBUG: Failed to parse time format: %s", itemData["notification"])
                                
                                # Parse subitems if present
                                subitems: List[Dict[str, Any]] = []
                                if "subitems" in itemData:
                                    for subitemData in itemData["subitems"]:
                                        if "title" in subitemData:
                                            subitems.append({"title": subitemData["title"], "isCompleted": False})
                                
                                # Create the checklist item
                                checklistItems.append({
                                    "title": itemData["title"],
                                    "date": date,
                                    "isCompleted": False,
                                    "notification": notificationDate,
                                    "group": group,
                                    "subItems": subitems
                                })
                                
                                logger.debug("CHECKLIST DEBUG: Added item: %s", itemData["title"])
                            else:
                                logger.warning("CHECKLIST DEBUG: Skipping item without title: %s", itemData)
                    
                    # Create and add the checklist
                    checklist = {
                        "id": str(uuid.uuid4()),
                        "date": date,
                        "items": checklistItems,
                        "notes": notes
                    }
                    
                    allChecklists.append(checklist)
                    logger.info("CHECKLIST DEBUG: Created checklist for %s with %d items and notes: %s", 
                              dateString, len(checklistItems), notes)
        
        logger.info("CHECKLIST DEBUG: Processed %d checklists in total", len(allChecklists))
        return None if not allChecklists else allChecklists 