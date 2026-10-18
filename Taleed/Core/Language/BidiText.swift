extension String {
    /// Keeps a left-to-right run, such as `@amina` or an email address, in order inside
    /// right-to-left text (Unicode LRI ... PDI). Without it, Arabic shows `amina@`.
    var isolatedLeftToRight: String { "\u{2066}\(self)\u{2069}" }

    /// Gives text written by members the direction of its own first strong letter
    /// (Unicode FSI ... PDI), whatever the app language is.
    var isolatedByContent: String { "\u{2068}\(self)\u{2069}" }
}
