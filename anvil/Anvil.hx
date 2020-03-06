package anvil;

import haxe.macro.Compiler;
import haxe.macro.Context;

using Lambda;

import sys.io.File;
import sys.FileSystem;
import haxe.PosInfos;

using haxe.io.Path;

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

typedef BuildResults = {
	var libs:Array<Path>; // list of dynamic library binaries/object files
}

class Anvil {
	static var runningDirectory:Path;

	static var pos:PosInfos;

	public static function run(?p:haxe.PosInfos) {
		pos = p;
		runningDirectory = new Path(Sys.getCwd());
		init();
		copyNativeToTargetDirectory();
		var results = buildTargetDirectory();

		deployAsDependency(results);
		Sys.setCwd(runningDirectory.toString());
	}

	static var nativeLibraryDirectory:Path;

	static function init() {
		getLibraryDirectory();
		getTargetDirectory();
	}

	static var config:AnvilConfig;

	static function getLibraryDirectory() {
		final thisPath = new haxe.io.Path(FileSystem.fullPath(pos.fileName));
		var basePath = new haxe.io.Path(FileSystem.fullPath('${thisPath.dir}'));
		while (!getAnvilConfig(basePath)) {
			basePath = new Path(FileSystem.fullPath('${basePath.dir}'));
		}
		nativeLibraryDirectory = new Path(haxe.io.Path.join([basePath.toString(), config.nativePath]));
	}

	static function getAnvilConfig(basePath:Path) {
		var configPath = '$basePath\\.anvilrc';
		if (!FileSystem.exists(configPath)) {
			return false;
		}
		config = haxe.Json.parse(sys.io.File.getContent(configPath));

		return true;
	}

	static var targetDirectory:Path;

	static function getTargetDirectory() {
		targetDirectory = new Path(Path.join([runningDirectory.toString(), 'native_extensions', config.ammerLib]));
	}

	static function copyFile(file:Path, dest:Path) {
		File.saveBytes(dest.toString(), File.getBytes(file.toString()));
	}

	static function copyDirectory(dir:Path, dest:Path) {
		if (!FileSystem.exists(dest.toString())) {
			FileSystem.createDirectory(dest.toString());
		}
		for (item in FileSystem.readDirectory(dir.toString())) {
			if (FileSystem.isDirectory(item)) {
				copyDirectory(dir, new Path(FileSystem.fullPath(Path.join([dest.toString(), item]))));
			} else {
				copyFile(new Path(Path.join([dir.toString(), item])), new Path(Path.join([dest.toString(), item])));
			}
		}
	}

	static function copyNativeToTargetDirectory() {
		copyDirectory(nativeLibraryDirectory, targetDirectory);
		#if macro
		var ammerIncludeDefine = 'ammer.lib.${config.ammerLib}.include';
		var ammerLibraryDefine = 'ammer.lib.${config.ammerLib}.library';
		Compiler.define(ammerIncludeDefine, Path.join([targetDirectory.toString(), config.includePath]));
		Compiler.define(ammerLibraryDefine, Path.join([targetDirectory.toString(), config.libPath]));
		#end
	}

	static var targetOutputDirectory:Path;

	static function buildTargetDirectory() {
		Sys.setCwd(targetDirectory.toString());
		if (config.verbose)
			Sys.command(config.buildCmd, config.buildArgs);
		else
			new sys.io.Process(config.buildCmd, config.buildArgs).exitCode(true);
		if (!FileSystem.exists(targetDirectory.toString()))
			FileSystem.createDirectory(targetDirectory.toString());
		targetOutputDirectory = new Path(Path.join([targetDirectory.toString(), config.libPath]));
		if (!FileSystem.exists(targetOutputDirectory.toString()))
			FileSystem.createDirectory(targetOutputDirectory.toString());
		return getBuildResults();
	}

	static var libExtensions:Array<String> = ['dll', 'dylib', 'so'];

	static function getBuildResults():BuildResults {
		return {
			libs: FileSystem.readDirectory(targetOutputDirectory.toString())
				.map(file -> new Path(FileSystem.fullPath(Path.join([targetOutputDirectory.toString(), file]))))
				.filter(fp -> libExtensions.indexOf(fp.ext) != -1)}
	}

	static function deployAsDependency(results:BuildResults) {
		var outputDir = "bin";
		#if macro
		if (!Context.defined('anvil.output')) {
			final platform = Context.defined('hl') ? 'hl' : Context.defined('lua') ? 'lua' : Context.defined('cpp') ? 'cpp' : '';
			outputDir = 'bin\\$platform';
			if (config.verbose)
				Context.warning('-D anvil.output flag missing, outputting to default folder "$outputDir"');
		} else {
			outputDir = Context.definedValue('anvil.output');
		}
		#else
		// if()
		#end

		var fullOutputDir = Path.join([runningDirectory.toString(), outputDir]);
		if (!FileSystem.exists(fullOutputDir))
			FileSystem.createDirectory(fullOutputDir);
		for (lib in results.libs) {
			copyFile(lib, new Path(FileSystem.fullPath(Path.join([fullOutputDir, lib.file.withExtension(lib.ext)]))));
		}
	}
}
