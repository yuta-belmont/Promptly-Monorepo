import Foundation

class SSEManager {
    private var eventSource: URLSessionDataTask?
    private var urlSession: URLSession?
    private var buffer: String = ""
    private var isConnected: Bool = false
    private var isClosed: Bool = false
    
    // Event handlers
    private var onEventHandler: ((String) -> Void)?
    private var onCompleteHandler: ((String) -> Void)?
    private var onErrorHandler: ((Error) -> Void)?
    
    // Stats for debugging
    private var eventsReceived: Int = 0
    private var lastEventTime: Date?
    
    func connect(requestId: String, baseURL: String = "http://192.168.1.166:8080", 
                 onEvent: @escaping (String) -> Void, 
                 onComplete: @escaping (String) -> Void,
                 onError: @escaping (Error) -> Void) {
        
        // Store handlers
        onEventHandler = onEvent
        onCompleteHandler = onComplete
        onErrorHandler = onError
        
        // Reset state
        buffer = ""
        eventsReceived = 0
        isConnected = false
        isClosed = false
        
        // Create URL for SSE endpoint
        let sseURL = URL(string: "\(baseURL)/api/v1/stream/\(requestId)")!
        
        // Create URLSession configuration with a longer timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0 // 60 seconds
        config.timeoutIntervalForResource = 300.0 // 5 minutes
        urlSession = URLSession(configuration: config)
        
        // Create and start the data task
        let task = urlSession?.dataTask(with: sseURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("SSE Error: \(error.localizedDescription)")
                self.isClosed = true
                self.onErrorHandler?(error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(domain: "SSEManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                self.isClosed = true
                self.onErrorHandler?(error)
                return
            }
            
            // Check response status code
            guard (200...299).contains(httpResponse.statusCode) else {
                let error = NSError(domain: "SSEManager", code: httpResponse.statusCode, 
                                   userInfo: [NSLocalizedDescriptionKey: "HTTP error \(httpResponse.statusCode)"])
                self.isClosed = true
                self.onErrorHandler?(error)
                return
            }
            
            // Connection established
            self.isConnected = true
            
            // Process data if available
            if let data = data, let text = String(data: data, encoding: .utf8) {
                self.processEventData(text)
            }
        }
        
        // Start the task
        task?.resume()
        eventSource = task
    }
    
    func disconnect() {
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
    
    private func processEventData(_ text: String) {
        // Add new data to buffer
        buffer += text
        
        // Process complete events in buffer
        while let eventRange = buffer.range(of: "data: ") {
            // Find the end of this event
            guard let eventEndRange = buffer[eventRange.upperBound...].range(of: "\n\n") else {
                // No complete event yet
                break
            }
            
            // Extract the event data
            let eventData = buffer[eventRange.upperBound..<eventEndRange.lowerBound]
            
            // Update stats
            eventsReceived += 1
            lastEventTime = Date()
            
            // Process the event
            processEvent(String(eventData))
            
            // Remove this event from buffer
            if let newRangeStart = buffer.index(eventEndRange.upperBound, offsetBy: 0, limitedBy: buffer.endIndex) {
                buffer = String(buffer[newRangeStart...])
            } else {
                buffer = ""
            }
        }
    }
    
    private func processEvent(_ eventData: String) {
        do {
            // Try to parse as JSON
            if let data = eventData.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                // Check for event type
                if let event = json["event"] as? String {
                    if event == "DONE" {
                        // This is a completion event
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
                        
                    } else if event == "ERROR" {
                        // This is an error event
                        let errorMessage = json["error"] as? String ?? "Unknown error"
                        let error = NSError(domain: "SSEManager", code: 0, 
                                           userInfo: [NSLocalizedDescriptionKey: errorMessage])
                        
                        DispatchQueue.main.async {
                            self.onErrorHandler?(error)
                        }
                        
                        // Connection is done
                        disconnect()
                    }
                } else if let chunk = json["chunk"] as? String {
                    // This is a data chunk
                    DispatchQueue.main.async {
                        self.onEventHandler?(chunk)
                    }
                }
            } else {
                // Not valid JSON, treat as plain text
                DispatchQueue.main.async {
                    self.onEventHandler?(eventData)
                }
            }
        } catch {
            print("Error parsing SSE event: \(error)")
            DispatchQueue.main.async {
                self.onEventHandler?(eventData)
            }
        }
    }
} 
