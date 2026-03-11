import SwiftUI

struct AddressBookView: View {
    @ObservedObject var manager = ConnectionManager.shared
    @State private var selectedType: ConnectionType = .drawThings
    @State private var selectedConnectionID: UUID?
    @State private var isEditing = false
    @State private var editingConnection: ServerConnection?
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control
            Picker("Connection Type", selection: $selectedType) {
                Text("Draw Things").tag(ConnectionType.drawThings)
                Text("Ollama").tag(ConnectionType.ollama)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Connection list
            List(filteredConnections, selection: $selectedConnectionID) { connection in
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.headline)
                    Text("\(connection.host):\(connection.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(connection.id)
            }
            .frame(minHeight: 150)

            Divider()

            // Test result
            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testResult.hasPrefix("OK") ? .green : .red)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            // Buttons
            HStack {
                Button("Add") {
                    editingConnection = ServerConnection(
                        id: UUID(),
                        name: "",
                        type: selectedType,
                        host: selectedType == .drawThings ? "127.0.0.1" : "127.0.0.1",
                        port: selectedType == .drawThings ? 7860 : 11434,
                        modelName: selectedType == .ollama ? "llava" : nil,
                        captionPrompt: selectedType == .ollama ? "Describe this image in detail for LoRA training captioning:" : nil
                    )
                    isEditing = true
                }

                Button("Edit") {
                    guard let id = selectedConnectionID,
                          let conn = manager.connection(for: id) else { return }
                    editingConnection = conn
                    isEditing = true
                }
                .disabled(selectedConnectionID == nil)

                Button("Delete") {
                    guard let id = selectedConnectionID else { return }
                    manager.delete(id: id)
                    selectedConnectionID = nil
                    testResult = nil
                }
                .disabled(selectedConnectionID == nil)

                Spacer()

                Button("Test Connection") {
                    guard let id = selectedConnectionID,
                          let conn = manager.connection(for: id) else { return }
                    testConnection(conn)
                }
                .disabled(selectedConnectionID == nil || isTesting)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
        .sheet(isPresented: $isEditing) {
            if let connection = editingConnection {
                ConnectionEditView(connection: connection, isPresented: $isEditing) { updated in
                    if manager.connections.contains(where: { $0.id == updated.id }) {
                        manager.update(updated)
                    } else {
                        manager.add(updated)
                        selectedConnectionID = updated.id
                    }
                }
            }
        }
        .onChange(of: selectedType) {
            selectedConnectionID = nil
            testResult = nil
        }
    }

    private var filteredConnections: [ServerConnection] {
        manager.connections(ofType: selectedType)
    }

    // MARK: - Test Connection

    private func testConnection(_ connection: ServerConnection) {
        isTesting = true
        testResult = nil

        Task {
            let result: String
            switch connection.type {
            case .drawThings:
                result = await testDrawThingsConnection(connection)
            case .ollama:
                result = await testOllamaConnection(connection)
            }
            isTesting = false
            testResult = result
        }
    }

    private func testDrawThingsConnection(_ conn: ServerConnection) async -> String {
        // Attempt a basic TCP connection to the gRPC port
        do {
            let url = URL(string: "http://\(conn.host):\(conn.port)")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return "OK — HTTP \(httpResponse.statusCode) (gRPC server responding)"
            }
            return "OK — Server responded"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func testOllamaConnection(_ conn: ServerConnection) async -> String {
        do {
            let url = URL(string: "http://\(conn.host):\(conn.port)/api/tags")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return "OK — Ollama is running"
            }
            return "Error: Unexpected response"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Connection Edit Sheet

struct ConnectionEditView: View {
    @State var connection: ServerConnection
    @Binding var isPresented: Bool
    var onSave: (ServerConnection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name:", text: $connection.name)
                TextField("Host:", text: $connection.host)
                TextField("Port:", value: $connection.port, format: .number)

                if connection.type == .ollama {
                    Divider()
                    TextField("Model Name:", text: Binding(
                        get: { connection.modelName ?? "" },
                        set: { connection.modelName = $0.isEmpty ? nil : $0 }
                    ))

                    Text("Caption Prompt:")
                    TextEditor(text: Binding(
                        get: { connection.captionPrompt ?? "" },
                        set: { connection.captionPrompt = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(connection)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(connection.name.isEmpty || connection.host.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: connection.type == .ollama ? 380 : 200)
    }
}
