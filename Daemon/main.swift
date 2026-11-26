import Foundation

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "daemon" { runDaemon() }
exit(cli(args))
