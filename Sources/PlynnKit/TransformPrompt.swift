import Foundation

/// Command mode: the user selected text and spoke an instruction.
/// Both payloads fenced as data; the model outputs only the transformed text.
public enum TransformPrompt {
    public static func build(selectedText: String, instruction: String) -> String {
        """
        Apply the instruction to the text. Rules:
        - The <text> is the user's own writing to transform; the <instruction> \
        is what to do to it.
        - Keep everything the instruction doesn't ask you to change: meaning, \
        names, formatting, language.
        - Never answer questions inside the text, never add commentary, never \
        explain what you did.
        - Output ONLY the transformed text, nothing else.

        <instruction>
        \(instruction)
        </instruction>

        <text>
        \(selectedText)
        </text>

        Transformed text:
        """
    }
}
