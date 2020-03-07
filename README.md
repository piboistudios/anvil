# `anvil`

A build tool for Haxe native extensions built using [`ammer`](https://github.com/Aurel300/ammer)

## What it does

`anvil` will allow users of a native library extension to build normally without having to perform native build maintenance tasks (like manually building the native code, or moving the binaries to projects that use it).

It provides a single class that provides a single static entry method for library authors to integrate their C/C++ build infrastructure into their haxelib.

In short, it will make sure all of your native library source files and binaries end up in the right place to be consumed by a user of your library and will attempt to build the source in the users project (hence the binaries end up in the right place)
All you need to do is include an initialization macro and an `.anvilrc` config file (JSON) at the root of your libraries project (and an ammer ready library), and all the user needs to do is include your library (and possibly specify other non-library specific config).
Not only will building projects with your native extensions build the native code (using your build command), but the Haxe compilation server may do so as well, allowing the IDE to offload native library building to a background service.

## TODO

Test MinGW
Test GC/Linux/OSX

## How it works

`anvil` provides a simple build script to simulate a cohesive Haxe/native extension build for a given native library.

A library author simply needs to reference the Anvil library via `-lib anvil` and create an initialization macro like so:
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
`anvil` determines the root directory of a haxe library (from the source file on the user's computer) by looking in parent directories for an `.anvilrc` file.

The `.anvilrc` is just a JSON representation of this Haxe typedef:
```haxe

typedef AnvilConfig = { // if you don't support a platform, users on that platform will be notifeid and anvil will exit.
	var ?windows:AnvilPlatformConfig;
	var ?linux:AnvilPlatformConfig;
	var ?bsd:AnvilPlatformConfig;
	var ?mac:AnvilPlatformConfig;
}

typedef AnvilPlatformConfig = {
	var ammerLib:String; // e.g. what you used to define -D ammer.lib.<ammerLib>.library etc...
	var nativePath:String; // the path to the native code from the root of your project
	var buildCmd:String; // the build command to run (this will run with the native path as its working directory; ensure all environment variables are set in order for this command to be successful)

	var ?outputBinaries:Array<String>; // list of binaries that need to be processed; if this isn't provided, anvil will infer what binaries to move
	// if anvil infers this, it will assume that if any library binary exists, the project was already fully built
	// otherwise it will compare the directory contents to the outputBinaries to determine if the project is already built
	//  when determining whether or not to skip compilation
	// i.e. If using MSVC toolchain, vsdevcmd.bat/vsvars32.bat need to be run in the shell before this.
	var ?buildArgs:Array<String>; // arguments for the build command. This works like Sys.command or new sys.io.Process, can be omitted (with args in cmd name)
	var ?verbose:Bool; // pipes the stdout of the build command to the stdout of the haxe build command.
	var ?libPath:String; // where the binaries are, if not at nativePath
	var ?includePath:String; // where the headers are if not at nativePath
	var ?deployInfo:{
		var type:DeployType; // with-user-output or to-path
		var ?dest:String; // if to-path, the destination path to put built binaries
	};
	var ?disableCache:Bool; // whether build caching is disabled. By default it will rebuild whenever any files in nativePath change
}

```

## Library Authors

Authors can also use this tool for testing, simply call the same initialization macro you put in `extraParams.hxml` in whatever.hxml file builds/runs your tests.

## Library Users

You can tell `anvil` where your output binaries will be so it can also move the required library binaries to your Haxe build output directory by using `-D anvil.output=<path>`
## Example
Because the test is located in the same repo as `anvil`, it is hard to tell what `anvil` really does.

Use Case: 
- a user will have a Haxe project probably somewhere, say `C:/User/Documents/projects`, and it contains an `hxml` (say, `C:/User/Documents/projects/build.hxml`)
-  your library will be located at something like `C:/Users/AppData/Roaming/Haxe/Haxelib/my_native_haxelib_extension/1,0,0,` 
- The user includes your haxe library, and its `extraParams.hxml` (where you put the Bootsrap code at)
- The user then runs `haxe build.hxml` at `C:/User/Documents/projects` to build their project including your library
- The Bootstrap kicks of `anvil`:

- `anvil` will then copy the `nativePath` (say `native`) from the `C:/Users/AppData/Roaming/Haxe/Haxelib/my_native_haxelib_extension/1,0,0,/native` directory to `C:/User/Documents/projects/native_extensions/$ammerLib` (say `$ammerLib` is `my_native_lib`)
- Set the CWD to `C:/User/Documents/projects/native_extensions/my_native_lib`
- Set the compiler flags `-D ammer.lib.<ammerLib>.library` and `-D ammer.lib.<ammerLib>.include` based on `libPath` and `includePath` relative to `C:/User/Documents/projects/native_extensions/my_native_lib` (this should allow the user's project to build smoothly; both `libPath` and `includePath` may be blank, in which case they are `nativePath`)
- Run `$buildCmd`
- Check for library binaries (`dll`, `dylib`, `so`) in the folder indicated by `ammer.lib.<ammerLib>.library` (i.e.: `C:/User/Documents/projects/native_extensions/my_native_lib`, assuming no `libPath` is set)
- Move them to the output folder specified by the user of your library (and other Ammer native extension libraries) with `-D anvil.output=where/user/puts/their/bins`
- Set CWD back to the original running directory
- Continue regular build process (at this point, your project should be able to be properly linked and utilized by the user)

## Projects using `anvil`
- [`hxdbc`](http://GitHub.com/piboistudios/hxdbc)
