using System.IO.Pipes;
using System.Security.Principal;
using System.Text;
using HIDMaestro;

internal static class Program
{
    private const string DefaultProfile = "xbox-360-wired";
    private const string DefaultIdentity = "mugen-deej-prototype";

    private static readonly string LogPath = Path.Combine(
        Path.GetTempPath(),
        "MugenDeej-VirtualGamepadHost.log"
    );

    private static int Main(string[] args)
    {
        try
        {
            if (args.Length == 0 || HasArg(args, "--help") || HasArg(args, "-h"))
            {
                PrintUsage();
                return 0;
            }

            if (args[0].Equals("server", StringComparison.OrdinalIgnoreCase))
            {
                return RunServer(args.Skip(1).ToArray());
            }

            Console.Error.WriteLine($"Unknown command: {args[0]}");
            PrintUsage();
            return 2;
        }
        catch (Exception ex)
        {
            Log("FATAL " + ex);
            Console.Error.WriteLine(ex.ToString());
            return 1;
        }
    }

    private static int RunServer(string[] args)
    {
        string? pipeName = GetArgValue(args, "--pipe");
        string profileId = GetArgValue(args, "--profile") ?? DefaultProfile;
        string identityKey = GetArgValue(args, "--identity") ?? DefaultIdentity;

        if (string.IsNullOrWhiteSpace(pipeName))
        {
            Console.Error.WriteLine("server requires --pipe <name>");
            return 2;
        }

        if (!IsAdministrator())
        {
            const string message = "Virtual controller host must run elevated because Windows requires admin rights to create the virtual HID device.";
            Log("ERROR " + message);
            Console.Error.WriteLine(message);
            return 5;
        }

        Log($"START profile={profileId}; identity={identityKey}; pipe={pipeName}");

        using var context = new HMContext();
        context.LoadDefaultProfiles();
        context.InstallDriver();

        var profile = context.GetProfile(profileId);
        if (profile is null)
        {
            throw new InvalidOperationException($"HIDMaestro profile not found: {profileId}");
        }

        using var controller = context.CreateController(profile, identityKey);

        var state = new HMGamepadState
        {
            Buttons = HMButton.None
        };
        controller.SubmitState(in state);

        using var pipe = new NamedPipeServerStream(
            pipeName,
            PipeDirection.InOut,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.None
        );

        Log("WAITING_FOR_CLIENT");
        pipe.WaitForConnection();
        Log("CLIENT_CONNECTED");

        var utf8 = new UTF8Encoding(false);
        using var reader = new StreamReader(pipe, utf8, false, 4096, leaveOpen: true);
        using var writer = new StreamWriter(pipe, utf8, 4096, leaveOpen: true)
        {
            AutoFlush = true,
            NewLine = "\n"
        };

        writer.WriteLine($"READY|{profileId}");

        try
        {
            while (pipe.IsConnected)
            {
                string? line = reader.ReadLine();
                if (line is null)
                {
                    break;
                }

                line = line.Trim();
                if (line.Length == 0)
                {
                    writer.WriteLine("OK");
                    continue;
                }

                if (line.Equals("ping", StringComparison.OrdinalIgnoreCase))
                {
                    writer.WriteLine("PONG");
                    continue;
                }

                if (line.Equals("release", StringComparison.OrdinalIgnoreCase))
                {
                    state.Buttons = HMButton.None;
                    controller.SubmitState(in state);
                    writer.WriteLine("OK");
                    continue;
                }

                if (line.Equals("quit", StringComparison.OrdinalIgnoreCase))
                {
                    state.Buttons = HMButton.None;
                    controller.SubmitState(in state);
                    writer.WriteLine("BYE");
                    break;
                }

                if (line.StartsWith("buttons ", StringComparison.OrdinalIgnoreCase))
                {
                    string valueText = line.Substring("buttons ".Length).Trim();
                    if (!uint.TryParse(valueText, out uint mask))
                    {
                        writer.WriteLine("ERR|invalid button mask");
                        continue;
                    }

                    state.Buttons = (HMButton)mask;
                    controller.SubmitState(in state);
                    writer.WriteLine("OK");
                    continue;
                }

                writer.WriteLine("ERR|unknown command");
            }
        }
        finally
        {
            try
            {
                state.Buttons = HMButton.None;
                controller.SubmitState(in state);
            }
            catch
            {
                // Best-effort release during teardown.
            }

            Log("STOP");
        }

        return 0;
    }

    private static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static bool HasArg(IEnumerable<string> args, string name)
        => args.Any(arg => arg.Equals(name, StringComparison.OrdinalIgnoreCase));

    private static string? GetArgValue(IReadOnlyList<string> args, string name)
    {
        for (int i = 0; i < args.Count - 1; i++)
        {
            if (args[i].Equals(name, StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }

        return null;
    }

    private static void PrintUsage()
    {
        Console.WriteLine("Mugen Deej Virtual Gamepad Host (prototype)");
        Console.WriteLine();
        Console.WriteLine("Usage:");
        Console.WriteLine("  MugenDeej.VirtualGamepadHost.exe server --pipe <name> [--profile xbox-360-wired] [--identity key]");
    }

    private static void Log(string message)
    {
        try
        {
            File.AppendAllText(
                LogPath,
                $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}",
                new UTF8Encoding(false)
            );
        }
        catch
        {
            // Logging must never stop the host.
        }
    }
}
