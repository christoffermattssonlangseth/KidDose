import SwiftUI
import SwiftData

struct AddChildSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedColor: Color = Color.presetChildColors[0]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Child's name", text: $name)
                        .autocorrectionDisabled()
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Color.presetChildColors, id: \.hexString) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if color.hexString == selectedColor.hexString {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { selectedColor = color }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Add Child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let child = Child(name: trimmed, colorHex: selectedColor.hexString)
                        context.insert(child)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
