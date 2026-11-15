import Foundation

/// Splits shell text into words the way a POSIX shell would, without running
/// anything: quotes are removed, backslash escapes applied, and unquoted
/// whitespace, newlines and `;&|()<>` end a word. Used to read alias and
/// function definitions printed by the user's shell.
///
/// With a `home`, `$HOME` / `${HOME}` (outside single quotes) and a leading
/// unquoted `~` / `~/` expand to it; every other `$…` stays literal. Without
/// one nothing is expanded, so a definition can be unquoted once and split again.
internal enum ShellWords {
    private struct Tokenizer {
        private static let separators: Set<Character> = [";", "&", "|", "(", ")", "<", ">"]
        private static let homeVariable = "HOME"

        let characters: [Character]
        let home: String?
        private var index = 0
        private var words: [String] = []
        private var current = ""
        private var inWord = false

        init(characters: [Character], home: String?) {
            self.characters = characters
            self.home = home
        }

        mutating func run() -> [String] {
            while let char = next() {
                switch char {
                case "'":
                    inWord = true
                    readSingleQuoted()

                case "\"":
                    inWord = true
                    readDoubleQuoted()

                case "\\":
                    readEscape()

                case "$":
                    inWord = true
                    current += readVariable()

                case "~" where !inWord:
                    inWord = true
                    current += expandTilde()

                default:
                    readPlain(char)
                }
            }
            finishWord()
            return words
        }

        private mutating func next() -> Character? {
            guard index < characters.count else {
                return nil
            }
            defer { index += 1 }
            return characters[index]
        }

        private func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        private mutating func readPlain(_ char: Character) {
            if char.isWhitespace || Self.separators.contains(char) {
                finishWord()
            } else {
                inWord = true
                current.append(char)
            }
        }

        private mutating func finishWord() {
            if inWord {
                words.append(current)
            }
            current = ""
            inWord = false
        }

        /// `\x` is a literal `x`; backslash-newline continues the line.
        private mutating func readEscape() {
            guard let escaped = next() else {
                return
            }
            if escaped != "\n" {
                inWord = true
                current.append(escaped)
            }
        }

        private mutating func readSingleQuoted() {
            while let char = next(), char != "'" {
                current.append(char)
            }
        }

        /// Inside double quotes a backslash only escapes `$`, `` ` ``, `"`, `\`
        /// and newline, and `$` still expands.
        private mutating func readDoubleQuoted() {
            while let char = next(), char != "\"" {
                if char == "\\", let escaped = peek(), "$`\"\\\n".contains(escaped) {
                    index += 1
                    if escaped != "\n" {
                        current.append(escaped)
                    }
                } else if char == "$" {
                    current += readVariable()
                } else {
                    current.append(char)
                }
            }
        }

        /// The text for a `$` just read: `home` for `$HOME` / `${HOME}` when
        /// expanding, else the variable reference unchanged.
        private mutating func readVariable() -> String {
            let braced = peek() == "{"
            if braced {
                index += 1
            }
            var name = ""
            while let char = peek(), char.isLetter || char.isNumber || char == "_" {
                name.append(char)
                index += 1
            }
            if braced, peek() == "}" {
                index += 1
            }
            if let home, name == Self.homeVariable {
                return home
            }
            return braced ? "${\(name)}" : "$" + name
        }

        /// A word-initial `~` followed by `/` or the end of the word.
        private func expandTilde() -> String {
            guard let home else {
                return "~"
            }
            guard let following = peek() else {
                return home
            }
            let endsWord = following.isWhitespace || Self.separators.contains(following)
            return following == "/" || endsWord ? home : "~"
        }
    }

    internal static func split(_ text: String, home: String? = nil) -> [String] {
        var tokenizer = Tokenizer(characters: Array(text), home: home)
        return tokenizer.run()
    }
}
