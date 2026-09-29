// Port of clap/examples/multicall-hostname.rs

function main() -> void {
    // `env!("CARGO_CRATE_NAME")`
    let cmd = root.clap.Command.new("multicall_hostname")
        .multicall(true)
        .arg_required_else_help(true)
        .subcommand_value_name("APPLET")
        .subcommand_help_heading("APPLETS")
        .subcommand(root.clap.Command.new("hostname").about("show hostname part of FQDN"))
        .subcommand(root.clap.Command.new("dnsdomainname").about("show domain name part of FQDN"));

    match (cmd.get_matches().subcommand_name()) {
        "hostname" => baml.io.println("www"),
        "dnsdomainname" => baml.io.println("example.com"),
        _ => baml.sys.panic("parser should ensure only valid subcommand names are used"),
    }
}
