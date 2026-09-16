using System.IO.Pipes;
using System.Security.Principal;
using System.Text;
using HIDMaestro;

internal static class Program
{
    private const string DefaultProfile = "xbox-360-wired";
    private const string DefaultIdentity = "mugen-deej-prototype";
    private const string DisplayName = "Mugen Deej Virtual Gamepad";

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

            if (args[0].Equals("cleanup", StringComparison.OrdinalIgnoreCase))
            {
                return RunCleanup();
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

    private static int RunCleanup()
    {
        if (!IsAdministrator())
        {
            const string message = "Virtual controller cleanup must run elevated.";
            Log("ERROR " + message);
            Console.Error.WriteLine(message);
            return 5;
        }

        Log("CLEANUP_START");

        try
        {
            int recovered = HMOemNameOverride.RecoverOrphans();
            Log($"OEM_NAME_RECOVERED count={recovered}");
        }
        catch (Exception ex)
        {
            Log("OEM_NAME_RECOVERY_ERROR " + ex);
        }

        HMContext.RemoveAllVirtualControllers(preserveInstall: true);
        Log("CLEANUP_DONE");
        Console.WriteLine("Mugen virtual controller cleanup completed.");
        return 0;
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

        ushort? overrideVid = null;
        ushort? overridePid = null;

        try
        {
            int recovered = HMOemNameOverride.RecoverOrphans();
            if (recovered > 0)
            {
                Log($"OEM_NAME_RECOVERED count={recovered}");
            }

            using var context = new HMContext();
            context.LoadDefaultProfiles();
            context.InstallDriver();

            var profile = context.GetProfile(profileId);
            if (profile is null)
            {
                throw new InvalidOperationException($"HIDMaestro profile not found: {profileId}");
            }

            using var controller = context.CreateController(profile, identityKey);

            // joy.cpl and DirectInput normally display the Xbox profile's
            // Microsoft OEM label. Claim a crash-safe HIDMaestro OEM-name
            // override while this virtual controller is live so users can
            // distinguish the Mugen-created device at a glance.
            overrideVid = profile.VendorId;
            overridePid = profile.ProductId;
            HMOemNameOverride.Set(profile.VendorId, profile.ProductId, DisplayName);
            Log($"OEM_NAME_SET vid={profile.VendorId:X4}; pid={profile.ProductId:X4}; label={DisplayName}");

            // Do not rely on an implicit all-zero struct as a neutral gamepad
            // frame. HIDMaestro's public state model uses normalized [0..1]
            // axes, where 0.5 is center for signed stick axes and 0.0 is the
            // released value for unsigned trigger axes. Seeding the complete
            // standard axis set keeps joy.cpl and games neutral before we ever
            // route a physical analog control.
            var state = new HMGamepadState
            {
                Axes = HMGamepadStateHelpers.StandardAxes(profile),
                Buttons = HMButton.None,
                Hat = HMHat.None
            };
            controller.SubmitState(in state);

            // The unelevated Mugen-side bridge owns the named-pipe server.
            // This elevated helper connects as the client. A lower-integrity
            // process can be blocked from opening an object created by the
            // elevated process even when both tokens belong to the same user;
            // reversing ownership avoids that UAC integrity boundary.
            using var pipe = new NamedPipeClientStream(
                ".",
                pipeName,
                PipeDirection.InOut,
                PipeOptions.None
            );

            Log("CONNECTING_TO_BRIDGE");
            pipe.Connect(60000);
            Log("BRIDGE_CONNECTED");

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
                        Log("BRIDGE_DISCONNECTED");
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
        }
        finally
        {
            if (overrideVid.HasValue && overridePid.HasValue)
            {
                try
                {
                    HMOemNameOverride.Clear(overrideVid.Value, overridePid.Value);
                    Log($"OEM_NAME_CLEARED vid={overrideVid.Value:X4}; pid={overridePid.Value:X4}");
                }
                catch (Exception ex)
                {
                    Log("OEM_NAME_CLEAR_ERROR " + ex);
                }
            }

            // Backstop after normal controller/context disposal. HIDMaestro's
            // explicit orphan sweep is intentionally preserved-install so a
            // Mugen exit never turns into a driver uninstall/reinstall cycle.
            try
            {
                Log("EXIT_SWEEP_START");
                HMContext.RemoveAllVirtualControllers(preserveInstall: true);
                Log("EXIT_SWEEP_DONE");
            }
            catch (Exception ex)
            {
                Log("EXIT_SWEEP_ERROR " + ex);
            }
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
        Console.WriteLine("  MugenDeej.VirtualGamepadHost.exe cleanup");
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
