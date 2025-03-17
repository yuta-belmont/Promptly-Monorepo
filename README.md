# Promptly

Promptly is an AI-powered mobile application that helps users create and manage checklists intelligently.

## Project Structure

This repository is organized as a monorepo containing two main components:

- **mobile/**: iOS mobile application written in Swift
- **server/**: Backend server (AlfredServer) written in Python

## Components

### Mobile Application

The mobile app provides a user-friendly interface for creating and managing checklists with the help of AI. It communicates with the backend server for AI processing tasks.

### Server (AlfredServer)

The server component handles AI-powered checklist generation using OpenAI's API. It includes an asynchronous worker system that processes checklist generation requests efficiently.

## Development

Both components have their own development workflows and dependencies. Please refer to the README files in each directory for specific setup and development instructions.

## Worker System

The server implements an asynchronous worker system capable of handling multiple concurrent AI processing tasks. The current configuration uses a single worker process that can handle up to 50 concurrent tasks and polls for new tasks every second. 