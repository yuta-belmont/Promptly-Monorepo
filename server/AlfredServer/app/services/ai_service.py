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
# MODELS
# =============================================================================
LOWEST_TIER_MODEL = "gpt-4o-mini-2024-07-18"
LOW_TIER_MODEL = "gpt-4.1-mini-2025-04-14"
MID_TIER_MODEL = "gpt-4.1-2025-04-14"

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
# Checklist Size Classifier Agent - Determines if a checklist is large/complex
# -------------------------------------------------------------------------
CHECKLIST_SIZE_CLASSIFIER_INSTRUCTIONS = """You are a checklist size classifier that determines if a user's request will result in a large or complex checklist.
YES: The checklist will span 5 or more days and have significant variety between days.
NO: The checklist will be shorter than 5 days or have similar tasks each day.

Respond with ONLY one word: either 'yes' or 'no'."""

# -------------------------------------------------------------------------
# Checklist Outline Generator Agent - Creates high-level plan structure
# -------------------------------------------------------------------------
CHECKLIST_OUTLINE_INSTRUCTIONS = """You are a checklist outline generator that creates a high-level structure for the user's plan.
Use the conversation context to understand the user's goals and timeframe.

Structure the outline based on the plan's duration:
- For plans spanning weeks: Break down by weeks
- For plans spanning several days: Break down by days
- If the start date is not specified, assume it starts today or tomorrow depending on the client time.

Each section should include:
1. Time period (e.g., "Week 1", "Month 2")
2. Main objectives for that period
3. Key milestones or deliverables

Keep the outline focused on the big picture - save specific tasks for the detailed checklist.

Format your response as a JSON object with the following structure:
{
    "outline": {
        "summary": "Brief description of the overall plan",
        "start_date": "YYYY-MM-DD",
        "end_date": "YYYY-MM-DD",
        "period": "week" or "day",
        "details": [
            {
                "title": "Week 1" or "Day 1",
                "breakdown": "Key objectives and milestones for this period"
            }
        ]
    }
}"""

# -------------------------------------------------------------------------
# Checklist Classifier Agent - Determines if a checklist should be generated
# -------------------------------------------------------------------------
CHECKLIST_CLASSIFIER_INSTRUCTIONS = """
You are a chat classifier inside a planner application that determines if a user wants to create a plan, task, reminder, or checklist of any kind.
Answer the following based on the user's most recent message:
YES: the user wants to add tasks, reminders, an outline,or plans to their planner.
NO: the user does not want to add tasks, reminders, or plans to their planner.
Respond with ONLY ONE word: either 'yes', or 'no'
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
Each item should have a clear title and, when requested (generally don't), a notification time in HH:MM format.
Be specific, practical, and thorough in creating these checklist items.
DO NOT over complicate simple tasks. A single item per day with a title is preffered.
No need to have a group name for simple checklists that span only a couple days or less.
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

# -------------------------------------------------------------------------
# Checklist Generator Agent - Creates detailed checklists from outlines
# -------------------------------------------------------------------------
CHECKLIST_FROM_OUTLINE_INSTRUCTIONS = """You are a detailed checklist generator that creates specific tasks from a plan outline.
Your goal is to break down each section of the outline into actionable tasks.

The outline details a broad plan that you have to turn into regular (often daily) tasks that the user can complete.

The group name should concisely describe the entire checklist in a word or 2. 
Ensure that:
- Tasks are specific and actionable
- The structure matches the original outline's time periods
- Each task has a clear completion criteria
- Try to stick to 1 item per day with subitems for more complex tasks.
- DO NOT add a notification time unless specified.

""" + CHECKLIST_FORMAT_INSTRUCTIONS

# -------------------------------------------------------------------------
# Check-in Analysis Agent - High level instructions
# -------------------------------------------------------------------------
CHECKIN_INSTRUCTIONS = """
Provide meaningful, personalized feedback based on their progress and aid in accountability.

{personality_prompt}

The user's stated objectives are: {user_objectives}

Consider:
1. Completion rate in the context of the historical data. Some tasks take many days to complete, so not marking off long term tasks as completed isn't necessarily a bad thing.
2. Patterns and trends in the historical data. It is important to bring up patterns in the data that the user may not have noticed.
3. The tasks in the context of the user's objectives.
4. The user may have messages in the notes that are important to consider in your analysis.
"""

# -------------------------------------------------------------------------
# Check-in Analysis Agent - JSON Formatting Instructions
# -------------------------------------------------------------------------
CHECKIN_AGENT_FORMAT_INSTRUCTIONS = """Please format your response as a JSON object with the following structure:
{
    "summary": "A one-sentence summary focused only on today's tasks and completion rate",
    "analysis": "Detailed analysis looking for patterns over time. Here you have to use context to determine if the task is a long term project or goal that takes many days to complete (clues may be in the historical data) or if a task is supposed to be a daily activity or habit.",
    "response": "Your response to the user's progress, tailored to their objectives in your personality. This should be concise and provide wisdon, clarity, and motivation."
}

If there is nothing to report, respond with an EXTREMELY concise message."""

PERSONALITY_PROMPTS = {
    "1": """You are enthusiastic and encouraging. Celebrate achievements with excitement and provide positive reinforcement. 
           Use upbeat language and focus heavily on what was accomplished.""",
    "2": """You are direct and concise. Keep responses brief and focused on essential information. 
           Avoid unnecessary elaboration.""",
    "3": """You are strict and focused on accountability like a drill sergeant. Maintain impossibly high standards and never be satisfied. 
           Emphasize responsibility and the importance of following through on commitments. Have distain for laziness as it leads to a miserable life."""
}

# Pydantic models for structured responses
class ChecklistSubItem(BaseModel):
    title: str
    is_completed: bool = False

class ChecklistItem(BaseModel):
    title: str
    notification: Optional[str] = None
    is_completed: bool = False
    subitems: Optional[List[ChecklistSubItem]] = []

class ChecklistDate(BaseModel):
    items: List[ChecklistItem]

class Group(BaseModel):
    name: str
    notes: Optional[str] = None
    items: List[ChecklistItem] = []

class ChecklistGroup(BaseModel):
    name: str
    notes: Optional[str] = None
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
            
            # Use mini model for classification - faster and still accurate for this task
            response = self.client.chat.completions.create(
                model=LOWEST_TIER_MODEL,  # Updated model name
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
            log_buffer.add(f"Model:" + LOWEST_TIER_MODEL)
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

            # Use mini model for classification - faster and still accurate for this task
            response = self.client.chat.completions.create(
                model=LOW_TIER_MODEL,  # Updated model name
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
            log_buffer.add(f"Model:" + LOW_TIER_MODEL)
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
                model=LOW_TIER_MODEL,
                messages=inquiry_messages,
                temperature=0.3,  # Lower temperature for more consistent classification
                max_tokens=5  # We only need a short response
            )
            
            # Get the classification result
            result = response.choices[0].message.content.strip().lower()
            
            # Determine the final result
            needs_more_info = 'more' in result
            
            logger.info(f"Output: Needs more information: {needs_more_info}")
            logger.debug(f"Context msgs: {len(context_messages)}")
            logger.debug(f"Model:" + LOW_TIER_MODEL)
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
                model=LOW_TIER_MODEL,
                messages=inquiry_messages,
                temperature=0.7,
                max_tokens=200  # Keep responses short
            )
            
            inquiry_response = response.choices[0].message.content
            
            logger.info(f"Output: \"{inquiry_response[:75]}{'...' if len(inquiry_response) > 75 else ''}\"")
            logger.debug(f"Context msgs: {len(context_messages)}")
            logger.debug(f"Model:" + LOW_TIER_MODEL)
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
                model="gpt-4.1-2025-04-14",  # Always use the more capable model for checklists
                messages=checklist_messages,
                temperature=0.7,
                max_tokens=10000,
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
                logger.debug(f"Model: gpt-4.1-2025-04-14")
                logger.info("=====================================")
                
                return checklist_data
                
            except json.JSONDecodeError as e:
                logger.error(f"Error parsing checklist JSON: {e}")
                logger.info(f"Output: Failed to parse JSON response")
                logger.debug(f"Context msgs: {len(context_messages)}")
                logger.debug(f"Model: gpt-4.1-2025-04-14")
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
                model=LOWEST_TIER_MODEL,
                messages=api_messages,
                temperature=0.7,
            )
            
            acknowledgment = response.choices[0].message.content
            
            # Log the response
            logger.info("=== AGENT: Checklist Acknowledgment Generator ===")
            logger.info(f"Input: \"{message[:50]}{'...' if len(message) > 50 else ''}\"")
            logger.info(f"Output: \"{acknowledgment[:75]}{'...' if len(acknowledgment) > 75 else ''}\"")
            logger.debug(f"Context msgs: {len(context_messages)}")
            logger.debug(f"Model:" + LOWEST_TIER_MODEL)
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
            message_model = MID_TIER_MODEL if query_type == "complex" else LOWEST_TIER_MODEL
            
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
                logger.info(f"Error with {message_model}, falling back to mini model: {e}")
                try:
                    # Try with the fallback model
                    response = self.client.chat.completions.create(
                        model=LOW_TIER_MODEL,
                        messages=api_messages,
                        temperature=0.7,
                    )
                    
                    conversation_response = response.choices[0].message.content
                    
                    logger.info(f"Output: \"{conversation_response[:75]}{'...' if len(conversation_response) > 75 else ''}\"")
                    logger.debug(f"Context msgs: {len(context_messages)}")
                    logger.debug(f"Model:"+ LOW_TIER_MODEL +"(fallback)")
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
    async def _classify_checklist_size(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None) -> bool:
        """Determine if the checklist will be large/complex."""
        try:
            response = self.client.chat.completions.create(
                model=LOW_TIER_MODEL,
                messages=[
                    {"role": "system", "content": CHECKLIST_SIZE_CLASSIFIER_INSTRUCTIONS},
                    *self._prepare_context_messages(message_history),
                    {"role": "user", "content": message}
                ],
                temperature=0.3,
                max_tokens=5
            )
            
            result = response.choices[0].message.content.strip().lower()
                        
            # Log a more structured view of the data for easier analysis
            logger.info("=================== AGENT CHECKLIST SIZE CLASSIFIER ===================")
            logger.info(f"IS CHECKLIST LARGE: {result}")
            logger.info("===============================================================")
            return 'yes' in result
        except Exception as e:
            logger.error(f"Error classifying checklist size: {e}")
            return False

    async def _generate_checklist_outline(self, message: str, message_history: Optional[List[Dict[str, Any]]] = None, client_time: Optional[str] = None) -> Dict[str, Any]:
        """Generate a high-level outline of the checklist."""
        try:
            # Use client_time for date calculations if provided
            current_date = datetime.now()
            if client_time:
                try:
                    current_date = datetime.fromisoformat(client_time)
                except ValueError:
                    print(f"Warning: Invalid client_time format: {client_time}")
            
            response = self.client.chat.completions.create(
                model=MID_TIER_MODEL,
                messages=[
                    {"role": "system", "content": CHECKLIST_OUTLINE_INSTRUCTIONS},
                    *self._prepare_context_messages(message_history),
                    {"role": "user", "content": message}
                ],
                temperature=0.7,
                response_format={"type": "json_object"}
            )
            
            return json.loads(response.choices[0].message.content)
        except Exception as e:
            logger.error(f"Error generating checklist outline: {e}")
            return None

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
                    # Check if this is a large checklist
                    is_large_checklist = await self._classify_checklist_size(message, message_history)
                    
                    if is_large_checklist:
                        # Generate outline
                        outline = await self._generate_checklist_outline(message, message_history, client_time)
                        
                        if outline:
                            # Return the outline directly
                            result['response_text'] = "I've created an outline for you. Let me know if you'd like to proceed with the detailed checklist."
                            result['outline'] = outline
                        else:
                            # Fallback to normal checklist if outline generation fails
                            result['response_text'] = await self._generate_checklist_acknowledgment(message, message_history, user_full_name, now)
                    else:
                        # Proceed with normal checklist generation
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

    def analyze_checkin(self, checklist_data: Dict[str, Any], user_full_name: Optional[str] = None, 
                       alfred_personality: Optional[str] = None, user_objectives: Optional[str] = None) -> Optional[str]:
        """
        Analyze a checklist and provide an encouraging response using GPT-4.
        
        Args:
            checklist_data: The checklist data to analyze
            user_full_name: The user's full name (optional)
            alfred_personality: The personality setting for Alfred (1=cheerleader, 2=minimalist, 3=disciplinarian)
            user_objectives: The user's stated objectives
            
        Returns:
            A JSON string containing summary, analysis, and response, or None if analysis fails
        """
        try:
            logger.info("Starting check-in analysis")
            
            # Check the structure of the data
            logger.info(f"Checklist data keys: {checklist_data.keys()}")
            
            # Extract today's checklist data - this is the top-level data, not in historical_data
            items = checklist_data.get('items', [])
            date = checklist_data.get('date', 'today')
            notes = checklist_data.get('notes', '')
            logger.info(f"Found {len(items)} items in today's checklist (date: {date})")
            
            # Extract historical data if available - should NOT include today's data
            historical_data = checklist_data.get('historical_data', [])
            
            # Log the dates from historical data to debug
            if historical_data:
                historical_dates = [hc.get('date', 'unknown') for hc in historical_data]
                logger.info(f"Historical data dates: {historical_dates}")
                
                # Check if today's date is in historical data (indicating duplication)
                if date in historical_dates:
                    logger.warning(f"Today's date ({date}) is also in historical data - may cause duplication")
            
            logger.info(f"Found {len(historical_data)} historical checklists")
            
            # If no items and no historical data, return a concise message
            if not items and not historical_data:
                logger.info("No items or historical data found, returning empty checklist response")
                return json.dumps({
                    "summary": "No tasks completed today",
                    "analysis": "No tasks were available for analysis",
                    "response": "Thanks for checking in. Keep up the great work!"
                })
            
            # Process today's data
            completed = sum(1 for item in items if item.get('is_completed', False))
            total = len(items)
            completion_percentage = (completed / total) * 100 if total > 0 else 0
            logger.info(f"Today's stats - Completed: {completed}, Total: {total}, Percentage: {completion_percentage:.1f}%")
            
            # Create a comprehensive analysis structure with three main sections
            analysis_data = {
                # Section 1: Historical context (all days prior to the most recent day)
                "historical_context": historical_data,
                
                # Section 2: Today's summary statistics
                "today_stats": {
                    "total_tasks": total,
                    "completed_tasks": completed,
                    "completion_percentage": completion_percentage
                },
                
                # Section 3: Today's detailed checklist (emphasized for AI)
                "today_checklist": {
                    "date": date,
                    "notes": notes,
                    "items": [
                        {
                            "title": item.get('title', ''),
                            "completed": item.get('is_completed', False),
                            "group": item.get('group').name if item.get('group') else ''
                        }
                        for item in items
                    ]
                }
            }
            
            # Add debug logging to see exactly what keys exist in the item
            
            # Get the personality prompt based on setting, default to minimalist if not specified
            personality_prompt = PERSONALITY_PROMPTS.get(str(alfred_personality), PERSONALITY_PROMPTS["2"])
            logger.info(f"Using personality prompt: {personality_prompt[:50]}...")
            
            # Format the instructions with personality and objectives
            system_message = CHECKIN_INSTRUCTIONS.format(
                personality_prompt=personality_prompt,
                user_objectives=user_objectives if user_objectives else "not specified"
            )
            
            # Create messages array with both instruction sets
            api_messages = [
                {"role": "system", "content": system_message},
                {"role": "system", "content": CHECKIN_AGENT_FORMAT_INSTRUCTIONS}
            ]
            
            # Create user message content
            user_message_content = f"Here is the checklist data for analysis:\n{json.dumps(analysis_data, indent=2)}"
            
            # Log a more structured view of the data for easier analysis
            logger.info("=================== STRUCTURED DATA BREAKDOWN ===================")
            logger.info(f"TODAY'S CHECKLIST DATE: {date}")
            logger.info(f"TODAY'S ITEMS COUNT: {len(items)}")
            logger.info(f"TODAY'S COMPLETION: {completed}/{total} ({completion_percentage:.1f}%)")
            
            if historical_data:
                logger.info(f"HISTORICAL DATA COUNT: {len(historical_data)} checklists")
            else:
                logger.info("NO HISTORICAL DATA")
            
            logger.info("===============================================================")
            
            # Add the comprehensive checklist data as a user message
            api_messages.append({
                "role": "user",
                "content": user_message_content
            })
            
            # Generate analysis using GPT-4 with explicit JSON response format
            logger.info("Sending request to GPT-4.1 with JSON response format")
            response = self.client.chat.completions.create(
                model=MID_TIER_MODEL,  # Use the more capable model for checkin analysis
                messages=api_messages,
                temperature=0.7,
                max_tokens=5000,
                response_format={"type": "json_object"}  # Explicitly request JSON response
            )
            
            # Print the raw response immediately after getting it
            raw_response = response.choices[0].message.content
            
            # Log the AI response
            logger.info("=================== AI RESPONSE ===================")
            logger.info(raw_response[:500] + ("..." if len(raw_response) > 500 else ""))
            logger.info("==================================================")
            
            # Get the analysis from the response
            analysis = raw_response.strip()
            
            # Try to parse the response as JSON
            try:
                # Clean the response string by removing any leading/trailing whitespace and newlines
                cleaned_analysis = analysis.strip()
                
                # Parse the JSON
                parsed_json = json.loads(cleaned_analysis)
                logger.info("Successfully parsed response as JSON")
                
                # Validate the required fields
                required_fields = ["summary", "analysis", "response"]
                for field in required_fields:
                    if field not in parsed_json:
                        logger.error(f"Missing required field in JSON response: {field}")
                        raise KeyError(f"Missing required field: {field}")
                
                # Return the original cleaned response
                return cleaned_analysis
                
            except json.JSONDecodeError as e:
                logger.error(f"Error parsing check-in response as JSON: {e}")
                logger.error(f"Raw response that failed to parse: {raw_response}")
                logger.error(f"Response length: {len(raw_response)}")
                logger.error(f"Response type: {type(raw_response)}")
                # If not JSON, wrap it in our structure
                wrapped_response = json.dumps({
                    "summary": f"Completed {completed} out of {total} tasks ({completion_percentage:.0f}%)",
                    "analysis": "Analyzing your progress and patterns",
                    "response": raw_response
                })
                logger.info(f"Wrapped response in JSON structure: {wrapped_response[:200]}...")
                return wrapped_response
            
        except Exception as e:
            logger.error(f"Error analyzing checkin: {e}")
            logger.error(f"Error type: {type(e)}")
            logger.error(f"Error args: {e.args}")
            logger.error(f"Raw response that caused error: {raw_response if 'raw_response' in locals() else 'No raw response available'}")
            # Provide a fallback response
            if total > 0:
                return json.dumps({
                    "summary": f"Completed {completed} out of {total} tasks",
                    "analysis": "Every step forward counts!",
                    "response": "You're making progress!"
                })
            return json.dumps({
                "summary": "No tasks completed",
                "analysis": "Keep up the great work!",
                "response": "Thanks for checking in!"
            }) 

    async def generate_checklist_from_outline(self, summary: str, start_date: str, end_date: str, line_items: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """
        Generate a detailed checklist from an outline.
        
        Args:
            summary: The summary of the plan
            start_date: The start date of the plan
            end_date: The end date of the plan
            line_items: The line items from the outline
            
        Returns:
            The generated checklist data or None if generation fails
        """
        try:
            # Create a prompt that includes the outline data
            prompt = f"""{CHECKLIST_FROM_OUTLINE_INSTRUCTIONS}

            Plan Summary: {summary}
            Start Date: {start_date}
            End Date: {end_date}

            Outline Structure:
            {json.dumps(line_items, indent=2)}

            Generate a detailed checklist that breaks down each section into specific tasks."""

            # Generate the checklist using the OpenAI client
            response = self.client.chat.completions.create(
                model=MID_TIER_MODEL,
                messages=[
                    {"role": "system", "content": CHECKLIST_FROM_OUTLINE_INSTRUCTIONS},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.7,
                max_tokens=2000
            )
            
            # Extract the response content
            checklist_text = response.choices[0].message.content
            
            # Parse the response
            try:
                checklist_data = json.loads(checklist_text)
                return checklist_data
            except json.JSONDecodeError:
                logger.error("Failed to parse checklist data from AI response")
                return None
                
        except Exception as e:
            logger.error(f"Error generating checklist from outline: {e}")
            return None 
