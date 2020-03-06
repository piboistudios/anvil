# Anvil

A build tool for Haxe native extensions built using [Ammer](https://github.com/Aurel300/ammer)

## What it does

Anvil will allow users of a native library extension to build normally without having to perform native build maintenance tasks (like manually building the native code, or moving the binaries to projects that use it).

It provides a simple interface for library authors to integrate their C/C++ build infrastructure into their haxelib.

## How it works

Anvil provides a simple build script to simulate a cohesive Haxe/native extension build for a given native library.

A library author simply needs to reference the Anvil library via `lib anvil` and create an initialization macro like so:
```haxe
class SimpleAnvilBootstrap {
    public static function run() {
        anvil.Anvil.run();
    }
}
```

Then in the library's `extraParams.hxml`:
```hxml
-D ammer.lib.<ammerLib>.library=<ammerLibPath>
-D ammer.lib.<ammerLib>.include=<ammerIncludePath>
--macro SimpleAnvilBootstrap.run()
```

This is necessary because Haxe passes a haxe.PosInfos object in when no argument is passed in for it, and passing it in from the HXML messes with the file path.

And `anvil.Anvil.run` is defined as `run(?pos:haxe.PosInfos)`.

Anvil determines the root directory of a haxe library (from the source file on the user's computer) by looking in parent directories for an `.anvilrc` file.
This means that assuming all Haxe package managers maintain a haxe library's project structure, Anvil should be able to identify the project's root and config file and get to work.

The `.anvilrc` is just a JSON representation of this Haxe typedef:
```haxe

typedef AnvilConfig = {
	var ammerLib:String; // e.g. what you used to define -D ammer.lib.<ammerLib>.library etc...
	var nativePath:String; // the path to the native code from the root of your project
	var buildCmd:String; // the build command to run (this will run with the native path as its working directory; ensure all environment variables are set in order for this command to be successful)
	// i.e. If using MSVC toolchain, vsdevcmd.bat/vsvars32.bat need to be run in the shell before this.
	var ?buildArgs:Array<String>; // arguments for the build command. This works like Sys.command or new sys.io.Process, can be omitted (with args in cmd name)
	var ?verbose:Bool; // pipes the stdout of the build command to the stdout of the haxe build command.
	var ?libPath:String; // where the binaries are, if not at nativePath
	var ?includePath:String; // where the headers are if not at nativePath
}
```


### Example
Because the test is located in the same repo as Anvil, it is hard to tell what Anvil really does.

Consider this example: 
- a user will have a Haxe project probably somewhere, say C:/Code/projects, and it contains an `hxml` (say, `C:/User/Documents/projects/build.hxml`)
-  your library will be located at something like `C:/Users/AppData/Roaming/Haxe/Haxelib/my_native_haxelib_extension/1,0,0,` 
- The user includes your haxe library, and its `extraParams.hxml` (where you put the Bootsrap code at)
- The user then runs `haxe build.hxml` at `C:/User/Documents/projects` to build their project including your library
- The Bootstrap kicks of Anvil:

- Anvil will then copy the `nativePath` (say `native`) from the `C:/Users/AppData/Roaming/Haxe/Haxelib/my_native_haxelib_extension/1,0,0,/native` directory to `C:/User/Documents/projects/native_extensions/$ammerLib` (say `$ammerLib` is `my_native_lib`)
- Set the CWD to `C:/User/Documents/projects/native_extensions/my_native_lib`
- Set the compiler flags `-D ammer.lib.<ammerLib>.library` and `-D ammer.lib.<ammerLib>.include` based on `libPath` and `includePath` relative to `C:/User/Documents/projects/native_extensions/my_native_lib` (this should allow the user's project to build smoothly; both `libPath` and `includePath` may be blank, in which case they are `nativePath`)
- Run `$buildCmd`
- Check for library binaries (`dll`, `dylib`, `so`) in the folder indicated by `ammer.lib.<ammerLib>.library` (i.e.: `C:/User/Documents/projects/native_extensions/my_native_lib`, assuming no `libPath` is set)
- Move them to the output folder specified by the user of your library (and other Ammer native extension libraries) with `-D anvil.output=where/user/puts/their/bins`
- Continue regular build process (at this point, your project should be able to be properly linked and utilized by the user)