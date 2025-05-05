import Foundation

class SSEManager: NSObject, URLSessionDataDelegate {
    private var eventSource: URLSessionDataTask?
    private var urlSession: URLSession?
    private var buffer: String = ""
    private var isConnected: Bool = false
    private var isClosed: Bool = false
    private var requestId: String = ""
    
    // Event handlers
    private var onEventHandler: ((String) -> Void)?
    private var onCompleteHandler: ((String) -> Void)?
    private var onErrorHandler: ((Error) -> Void)?
    
    // Stats for debugging
    private var eventsReceived: Int = 0
    private var lastEventTime: Date?
    
    override init() {
        super.init()
    }
    
    func connect(requestId: String, baseURL: String = "http://192.168.1.166:8080", 
                 onEvent: @escaping (String) -> Void, 
                 onComplete: @escaping (String) -> Void,
                 onError: @escaping (Error) -> Void) {
        
        // Store handlers
        onEventHandler = onEvent
        onCompleteHandler = onComplete
        onErrorHandler = onError
        self.requestId = requestId
        
        // Reset state
        buffer = ""
        eventsReceived = 0
        isConnected = false
        isClosed = false
        
        // Create URL for SSE endpoint
        let sseURL = URL(string: "\(baseURL)/api/v1/stream/\(requestId)")!
        
        // Create URLSession with delegate for streaming support
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0 // 60 seconds
        config.timeoutIntervalForResource = 300.0 // 5 minutes
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        // Create and start the data task
        var request = URLRequest(url: sseURL)
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        let task = urlSession?.dataTask(with: request)
        task?.resume()
        eventSource = task
        
        print("SSE: Started connection to \(sseURL) for request ID: \(requestId)")
    }
    
    func disconnect() {
        print("SSE: Disconnecting for request ID: \(requestId)")
        
        // Cancel task and cleanup
        eventSource?.cancel()
        eventSource = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        isClosed = true
        
        // Clear handlers
        onEventHandler = nil
        onCompleteHandler = nil
        onErrorHandler = nil
    }
    
    // MARK: - URLSessionDataDelegate Methods
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            let error = NSError(domain: "SSEManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            onErrorHandler?(error)
            completionHandler(.cancel)
            return
        }
        
        // Check response status code
        guard (200...299).contains(httpResponse.statusCode) else {
            let error = NSError(domain: "SSEManager", code: httpResponse.statusCode, 
                               userInfo: [NSLocalizedDescriptionKey: "HTTP error \(httpResponse.statusCode)"])
            onErrorHandler?(error)
            completionHandler(.cancel)
            return
        }
        
        // Connection established
        isConnected = true
        print("SSE: Connection established for request ID: \(requestId)")
        
        // Allow the connection to proceed
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Convert data to string and add to buffer
        if let text = String(data: data, encoding: .utf8) {
            print("SSE: Received \(data.count) bytes for request ID: \(requestId)")
            processEventData(text)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("SSE: Connection error for request ID: \(requestId) - \(error.localizedDescription)")
            if !isClosed {
                onErrorHandler?(error)
                disconnect()
            }
        } else if !isClosed {
            // Connection completed normally but no explicit completion message
            print("SSE: Connection completed normally for request ID: \(requestId)")
            onCompleteHandler?("")
            disconnect()
        }
    }
    
    // MARK: - Event Processing
    
    private func processEventData(_ text: String) {
        // Add new data to buffer
        buffer += text
        
        // Process complete events in buffer
        processEventsFromBuffer()
    }
    
    private func processEventsFromBuffer() {
        // We need to parse the event type line as well as the data line
        var currentEvent = "message" // default event type
        
        // Look for complete SSE messages (data: ... followed by \n\n)
        // But also check for event: lines
        while true {
            // Check if we have an event type line
            if let eventTypeRange = buffer.range(of: "event: ") {
                if let eventEndRange = buffer[eventTypeRange.upperBound...].range(of: "\n") {
                    // Extract the event type
                    currentEvent = String(buffer[eventTypeRange.upperBound..<eventEndRange.lowerBound])
                    
                    // Remove this event type line from buffer
                    if eventEndRange.upperBound < buffer.endIndex {
                        buffer = String(buffer[eventEndRange.upperBound...])
                    } else {
                        buffer = ""
                        break // Buffer is empty now
                    }
                    
                    print("SSE: Found event type: \(currentEvent) for request ID: \(requestId)")
                    continue // Continue to process next line
                }
            }
            
            // Look for data line
            if let dataRange = buffer.range(of: "data: ") {
                // Find the end of this event
                guard let eventEndRange = buffer[dataRange.upperBound...].range(of: "\n\n") else {
                    // No complete event yet, wait for more data
                    print("SSE: Partial event in buffer for request ID: \(requestId), waiting for more data")
                    return
                }
                
                // Extract the event data
                let eventData = String(buffer[dataRange.upperBound..<eventEndRange.lowerBound])
                
                // Update stats
                eventsReceived += 1
                lastEventTime = Date()
                
                print("SSE: Processing event #\(eventsReceived) type: \(currentEvent) for request ID: \(requestId)")
                
                // Process the event based on its type
                processEvent(eventData, eventType: currentEvent)
                
                // Reset event type to default after processing
                currentEvent = "message"
                
                // Remove this event from buffer
                if eventEndRange.upperBound < buffer.endIndex {
                    buffer = String(buffer[eventEndRange.upperBound...])
                } else {
                    buffer = ""
                    break // Buffer is empty now
                }
            } else {
                // No more events to process
                break
            }
        }
    }
    
    private func processEvent(_ eventData: String, eventType: String) {
        do {
            // Ignore connected events completely - don't pass them to UI
            if eventType == "connected" {
                print("SSE: Received connection event for request ID: \(requestId), ignoring for UI")
                return
            }
            
            // Only process text chunks and completion events
            if eventType == "text" || eventType == "done" || eventType == "error" {
                // Try to parse as JSON
                if let data = eventData.data(using: .utf8),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if eventType == "done" {
                        // This is a completion event
                        print("SSE: Received DONE event for request ID: \(requestId)")
                        if let fullText = json["full_text"] as? String {
                            // Call completion handler with full text
                            DispatchQueue.main.async {
                                self.onCompleteHandler?(fullText)
                            }
                        } else {
                            // Call completion with empty string if no full text
                            DispatchQueue.main.async {
                                self.onCompleteHandler?("")
                            }
                        }
                        
                        // Connection is done
                        disconnect()
                        
                    } else if eventType == "error" {
                        // This is an error event
                        let errorMessage = json["error"] as? String ?? "Unknown error"
                        print("SSE: Received ERROR event for request ID: \(requestId) - \(errorMessage)")
                        let error = NSError(domain: "SSEManager", code: 0, 
                                           userInfo: [NSLocalizedDescriptionKey: errorMessage])
                        
                        DispatchQueue.main.async {
                            self.onErrorHandler?(error)
                        }
                        
                        // Connection is done
                        disconnect()
                        
                    } else if let chunk = json["chunk"] as? String {
                        // This is a data chunk from a text event
                        print("SSE: Received chunk of length \(chunk.count) for request ID: \(requestId)")
                        DispatchQueue.main.async {
                            self.onEventHandler?(chunk)
                        }
                    } else {
                        // Unknown JSON format - log it but don't send to UI
                        print("SSE: Received unknown JSON format for text event: \(json)")
                    }
                } else {
                    // Not valid JSON - log it but don't send to UI for text events
                    print("SSE: Received non-JSON data for event type: \(eventType)")
                    
                    // Only pass the raw data for message events (default), not for text/connected events
                    if eventType == "message" {
                        DispatchQueue.main.async {
                            self.onEventHandler?(eventData)
                        }
                    }
                }
            } else {
                // Unknown event type - log but don't send to UI
                print("SSE: Received unknown event type: \(eventType)")
            }
        } catch {
            print("SSE: Error parsing event for request ID: \(requestId) - \(error)")
            
            // Only send raw data for message events (default), not for structured events
            if eventType == "message" {
                DispatchQueue.main.async {
                    self.onEventHandler?(eventData)
                }
            }
        }
    }
} 
