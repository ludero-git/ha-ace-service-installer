using System;
using System.IO;
using System.Linq;
using System.Xml;
using Mono.Cecil;
using Mono.Cecil.Cil;

internal static class Program
{
    private static int Main(string[] args)
    {
        // Expect exactly one argument pointing to the target directory.
        if (args.Length != 1 || !Directory.Exists(args[0]))
        {
            Console.Error.WriteLine(
                "Usage: ServiceInstallerPatcher.exe <directory>");

            return 1;
        }

        try
        {
            string dir = Path.GetFullPath(args[0]);

            PatchXwt(
                Path.Combine(dir, "Xwt.dll"));

            PatchMdns(
                Path.Combine(dir, "Tmds.MDns.dll"));

            PatchConfig(
                Path.Combine(dir, "ACEServiceInstaller.exe.config"));

            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                "Patch failed: " + ex.Message);

            return 1;
        }
    }

    private static MethodDefinition FindMethod(
        AssemblyDefinition asm,
        string typeName,
        string methodName,
        params string[] parameterTypes)
    {
        var type = asm.MainModule.Types
            .FirstOrDefault(t => t.FullName == typeName);

        if (type == null)
        {
            throw new InvalidOperationException(
                "Type not found: " + typeName);
        }

        var method = type.Methods
            .FirstOrDefault(m =>
                m.Name == methodName &&
                m.Parameters
                    .Select(p => p.ParameterType.FullName)
                    .SequenceEqual(parameterTypes));

        if (method == null)
        {
            throw new InvalidOperationException(
                $"Method not found: {typeName}.{methodName}");
        }

        return method;
    }

    private static bool IsReference(
        Instruction instruction,
        OpCode opcode,
        string typeName,
        string methodName,
        params string[] parameterTypes)
    {
        if (instruction.OpCode != opcode ||
            !(instruction.Operand is MethodReference method))
        {
            return false;
        }

        return
            method.DeclaringType.FullName == typeName &&
            method.Name == methodName &&
            method.Parameters
                .Select(p => p.ParameterType.FullName)
                .SequenceEqual(parameterTypes);
    }

    private static void Backup(string path)
    {
        // Keep a copy of the original file before modifying it.
        File.Copy(
            path,
            path + ".bak",
            true);
    }

    private static void WriteAssembly(
        AssemblyDefinition asm,
        string path)
    {
        string temp = path + ".tmp";

        if (File.Exists(temp))
        {
            File.Delete(temp);
        }

        // Write to a temporary file before replacing the original.
        asm.Write(temp);
        asm.Dispose();

        File.Delete(path);
        File.Move(temp, path);
    }

    private static void PatchXwt(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException(
                "Xwt.dll not found",
                path);
        }

        var asm = AssemblyDefinition.ReadAssembly(path);

        var method = FindMethod(
            asm,
            "Xwt.StockIcons",
            "GetIcon",
            "System.String");

        var instructions = method.Body.Instructions;

        // Patched method should contain only: ldnull; ret.
        bool patched =
            instructions.Count == 2 &&
            instructions[0].OpCode == OpCodes.Ldnull &&
            instructions[1].OpCode == OpCodes.Ret;

        if (patched)
        {
            asm.Dispose();

            Console.WriteLine(
                "Xwt.dll already patched");

            return;
        }

        asm.Dispose();

        Backup(path);

        asm = AssemblyDefinition.ReadAssembly(path);

        method = FindMethod(
            asm,
            "Xwt.StockIcons",
            "GetIcon",
            "System.String");

        // Replace the existing method body with a simple null return.
        method.Body.ExceptionHandlers.Clear();
        method.Body.Variables.Clear();
        method.Body.Instructions.Clear();

        var il = method.Body.GetILProcessor();

        il.Append(
            il.Create(OpCodes.Ldnull));

        il.Append(
            il.Create(OpCodes.Ret));

        WriteAssembly(
            asm,
            path);

        Console.WriteLine(
            "Xwt.dll patched");
    }

    private static void PatchMdns(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException(
                "Tmds.MDns.dll not found",
                path);
        }

        var asm = AssemblyDefinition.ReadAssembly(path);

        var method = FindMethod(
            asm,
            "Tmds.MDns.NetworkInterfaceHandler",
            "CreateIpv4Socket",
            "System.Int32");

        var instructions =
            method.Body.Instructions.ToList();

        // Check whether the original HostToNetworkOrder call still exists.
        bool hasHostCall = instructions.Any(
            instruction =>
                IsReference(
                    instruction,
                    OpCodes.Call,
                    "System.Net.IPAddress",
                    "HostToNetworkOrder",
                    "System.Int32"));

        int patchedMulticast = 0;

        // Look for an already-patched multicast constructor argument.
        for (int i = 0; i < instructions.Count - 1; i++)
        {
            bool loadsZero =
                instructions[i].OpCode == OpCodes.Ldc_I4_0;

            bool createsMulticastOption =
                IsReference(
                    instructions[i + 1],
                    OpCodes.Newobj,
                    "System.Net.Sockets.MulticastOption",
                    ".ctor",
                    "System.Net.IPAddress",
                    "System.Int32");

            if (loadsZero && createsMulticastOption)
            {
                patchedMulticast++;
            }
        }

        if (!hasHostCall && patchedMulticast == 1)
        {
            asm.Dispose();

            Console.WriteLine(
                "Tmds.MDns.dll already patched");

            return;
        }

        asm.Dispose();

        Backup(path);

        asm = AssemblyDefinition.ReadAssembly(path);

        method = FindMethod(
            asm,
            "Tmds.MDns.NetworkInterfaceHandler",
            "CreateIpv4Socket",
            "System.Int32");

        instructions =
            method.Body.Instructions.ToList();

        // Find the interface-index conversion sequence.
        var patch1 = instructions
            .Zip(
                instructions.Skip(1),
                (a, b) => new { a, b })
            .Where(x =>
                x.a.OpCode == OpCodes.Ldarg_0 &&
                IsReference(
                    x.b,
                    OpCodes.Call,
                    "System.Net.IPAddress",
                    "HostToNetworkOrder",
                    "System.Int32"))
            .ToList();

        // Find the interface-index argument passed to MulticastOption.
        var patch2 = instructions
            .Zip(
                instructions.Skip(1),
                (a, b) => new { a, b })
            .Where(x =>
                x.a.OpCode == OpCodes.Ldarg_0 &&
                IsReference(
                    x.b,
                    OpCodes.Newobj,
                    "System.Net.Sockets.MulticastOption",
                    ".ctor",
                    "System.Net.IPAddress",
                    "System.Int32"))
            .ToList();

        // Refuse to patch if the expected IL layout has changed.
        if (patch1.Count != 1 || patch2.Count != 1)
        {
            asm.Dispose();

            throw new InvalidOperationException(
                $"Unexpected Tmds.MDns IL: " +
                $"patch1={patch1.Count}, " +
                $"patch2={patch2.Count}");
        }

        // Replace the HostToNetworkOrder sequence with a constant zero.
        patch1[0].a.OpCode = OpCodes.Ldc_I4_0;
        patch1[0].a.Operand = null;

        patch1[0].b.OpCode = OpCodes.Nop;
        patch1[0].b.Operand = null;

        // Use zero for the MulticastOption interface index.
        patch2[0].a.OpCode = OpCodes.Ldc_I4_0;
        patch2[0].a.Operand = null;

        WriteAssembly(
            asm,
            path);

        Console.WriteLine(
            "Tmds.MDns.dll patched");
    }

    private static void PatchConfig(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException(
                "ACEServiceInstaller.exe.config not found",
                path);
        }

        const string oldValue =
            ".NETFramework,Version=v4.8.1";

        const string newValue =
            ".NETFramework,Version=v4.8";

        var document = new XmlDocument();

        document.PreserveWhitespace = true;
        document.Load(path);

        XmlNode supportedRuntime =
            document.SelectSingleNode(
                "/configuration/startup/supportedRuntime");

        if (supportedRuntime == null)
        {
            throw new InvalidOperationException(
                "supportedRuntime element not found in " +
                "ACEServiceInstaller.exe.config");
        }

        XmlAttribute skuAttribute = null;

        if (supportedRuntime.Attributes != null)
        {
            skuAttribute =
                supportedRuntime.Attributes["sku"];
        }

        if (skuAttribute == null)
        {
            throw new InvalidOperationException(
                "supportedRuntime sku attribute not found in " +
                "ACEServiceInstaller.exe.config");
        }

        if (skuAttribute.Value == newValue)
        {
            Console.WriteLine(
                "ACEServiceInstaller.exe.config already patched");

            return;
        }

        if (skuAttribute.Value != oldValue)
        {
            throw new InvalidOperationException(
                "Unexpected supportedRuntime sku: " +
                skuAttribute.Value);
        }

        // Keep a copy of the original config before modifying it.
        Backup(path);

        skuAttribute.Value = newValue;

        string temp =
            path + ".tmp";

        if (File.Exists(temp))
        {
            File.Delete(temp);
        }

        // Write the modified XML to a temporary file first.
        document.Save(temp);

        // Replace the original only after the temporary file
        // has been written successfully.
        File.Delete(path);
        File.Move(temp, path);

        Console.WriteLine(
            "ACEServiceInstaller.exe.config patched");
    }
}