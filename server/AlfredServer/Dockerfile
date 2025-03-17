FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire project
COPY . .

# Set the Python path
ENV PYTHONPATH=/app

# Make the start script executable
RUN chmod +x /app/start.sh

# Use PORT environment variable with fallback to 8080
CMD ["/app/start.sh"] 