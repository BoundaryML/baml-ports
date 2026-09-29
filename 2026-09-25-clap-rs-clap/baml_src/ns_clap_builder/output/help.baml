// Port of clap_builder/src/output/help.rs

/// Writes the parser help to the wrapped stream.
function write_help(writer: StyledStr, cmd: Command, usage: Usage, use_long: bool) -> void {
    if let h: StyledStr = cmd.get_override_help() {
        writer.push_styled(h);
    } else if (features().help) {
        if let tmpl: StyledStr = cmd.get_help_template() {
            HelpTemplate.new(writer, cmd, usage, use_long)
                .write_templated_help(tmpl.as_styled_str());
        } else {
            AutoHelp.new(writer, cmd, usage, use_long).write_help();
        }
    }

    // Remove any lines from unused sections
    writer.trim_start_lines();
    // Remove any whitespace caused by book keeping
    writer.trim_end();
    // Ensure there is still a trailing newline
    writer.push_str("\n");
}
