import SwiftUI

struct RecipeCategoryCreationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var categoryName: String
    @Binding var categoryEmoji: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Text(categoryEmoji)
                                .font(.system(size: 60))
                            Text(categoryName.isEmpty ? "Recipe Category Name" : categoryName)
                                .font(DesignSystem.Typography.title3)
                                .foregroundStyle(
                                    categoryName.isEmpty
                                    ? DesignSystem.Colors.secondary
                                    : DesignSystem.Colors.primary
                                )
                        }
                        .padding(.vertical, DesignSystem.Spacing.grid_2)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                Section("Category Details") {
                    TextField("Recipe Category Name", text: $categoryName)
                        .padding(.vertical, 4)
                }

                Section("Choose Icon") {
                    RecipeEmojiPicker(selectedEmoji: $categoryEmoji)
                        .padding(.vertical, 8)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Recipe Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave()
                    }
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }
}

private struct RecipeEmojiPicker: View {
    @Binding var selectedEmoji: String

    private let emojis = [
        "🥣", "☕️", "🥤", "🍵", "🍫", "🧋",
        "🍞", "🥐", "🥖", "🧁", "🍰", "🍪",
        "🥗", "🍲", "🍝", "🍳", "🧂", "🫙",
        "🌱", "🥛", "🧈", "🍓", "🍋", "🥜"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                        DesignSystem.HapticFeedback.trigger(.selection)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 32))
                            .padding(8)
                            .background(selectedEmoji == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}
