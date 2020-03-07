package anvil;

import haxe.macro.Compiler;
import haxe.macro.Context;

using Lambda;

import sys.io.File;
import sys.FileSystem;
import haxe.PosInfos;

using haxe.io.Path;

enum abstract DeployType(String) {
	var WithUserOutput = 'with-user-output';
	var ToPath = 'to-path';
}

typedef AnvilConfig = {
	var ?windows:Array<AnvilPlatformConfig>;
	var ?linux:Array<AnvilPlatformConfig>;
	var ?bsd:Array<AnvilPlatformConfig>;
	var ?mac:Array<AnvilPlatformConfig>;
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

typedef BuildResults = {
	var libs:Array<Path>; // list of dynamic library binaries/object files
}

class Anvil {
	static var runningDirectory:Path;
	static var haxelibPath = Sys.getEnv('HAXELIB_PATH');
	static var pos:PosInfos;

	public static function run(?p:haxe.PosInfos) {
		pos = p;
		runningDirectory = new Path(Sys.getCwd());
		if (!init())
			return;
		for (c in configs) {
			config = c;
			getNativeLibraryDirectory();
			getTargetDirectory();
			copyNativeToTargetDirectory();
			var results = buildTargetDirectory();
			config.deployInfo = config.deployInfo != null ? config.deployInfo : {type: WithUserOutput};
			switch config.deployInfo.type {
				case WithUserOutput:
					deployAsDependency(results);
				case ToPath:
					deployToDirectory(results);
			}
		}
		Sys.setCwd(runningDirectory.toString());
	}

	static var nativeLibraryDirectory:Path;
	static var platform = Sys.systemName().toLowerCase();
	static var configs:Array<AnvilPlatformConfig>;

	static function init() {
		final _trace = haxe.Log.trace;
		haxe.Log.trace = (msg, ?pos:haxe.PosInfos) -> {
			#if macro
			Context.info(msg, Context.currentPos());
			#else
			_trace(msg, pos);
			#end
			return;
		};
		getConfigs();
		if (configs == null) {
			trace('Unable to find anvil configuration for the desired platform. $platform.');
			trace('Aborting');
			return false;
		}

		return true;
	}

	static var config:AnvilPlatformConfig;
	static var basePath:Path;

	static function getConfigs() {
		final thisPath = new haxe.io.Path(FileSystem.fullPath(pos.fileName));
		basePath = new haxe.io.Path(FileSystem.fullPath('${thisPath.dir}'));
		while (!getAnvilConfigs(basePath)) {
			basePath = new Path(FileSystem.fullPath('${basePath.dir}'));
		}
	}

	static function getNativeLibraryDirectory() {
		nativeLibraryDirectory = new Path(haxe.io.Path.join([basePath.toString(), config.nativePath]));
	}

	static function getAnvilConfigs(basePath:Path) {
		var configPath = '$basePath\\.anvilrc';
		if (!FileSystem.exists(configPath)) {
			return false;
		}
		final globalConfig:haxe.DynamicAccess<Dynamic> = haxe.Json.parse(sys.io.File.getContent(configPath));
		configs = globalConfig[platform];
		if (configs == null)
			configs = globalConfig['all'];
		if (configs == null)
			return true;
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
		if (dir == null || dest == null)
			return;
		if (!FileSystem.exists(dest.toString())) {
			FileSystem.createDirectory(dest.toString());
		}
		for (item in FileSystem.readDirectory(dir.toString())) {
			final fullItemPath = new Path(Path.join([dir.toString(), item]));
			final fullDestPath = new Path(Path.join([dest.toString(), item]));
			if (FileSystem.isDirectory(item)) {
				copyDirectory(fullItemPath, fullDestPath);
			} else {
				copyFile(fullItemPath, fullDestPath);
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

	static function willSkipBuild(state:BuildResults) {
		final ret = (config.outputBinaries == null || config.outputBinaries.length == 0) ? state.libs.length != 0 : config.outputBinaries.foreach(bin ->
			state.libs.exists((lib:Path) -> lib.file.withExtension(lib.ext)
			.toLowerCase() == bin.toLowerCase()));
		if (config.verbose && ret)
			trace("SKIPPING BUILD STEP");
		return ret;
	}

	static function buildTargetDirectory() {
		targetOutputDirectory = new Path(Path.join([targetDirectory.toString(), config.libPath]));
		final initialState = getBuildResults();
		if (#if macro !Context.defined('--force-anvil') && #end (willSkipBuild(initialState) && !config.disableCache)) {
			return {libs: []};
		}
		Sys.setCwd(targetDirectory.toString());
		if (config.verbose)
			Sys.command(config.buildCmd, config.buildArgs);
		else
			new sys.io.Process(config.buildCmd, config.buildArgs).exitCode(true);
		if (!FileSystem.exists(targetDirectory.toString()))
			FileSystem.createDirectory(targetDirectory.toString());

		if (!FileSystem.exists(targetOutputDirectory.toString()))
			FileSystem.createDirectory(targetOutputDirectory.toString());
		return getBuildResults();
	}

	static var libExtensions:Array<String> = ['dll', 'dylib', 'so'];

	static function getBuildResults():BuildResults {
		return {
			libs: targetOutputDirectory == null ? [] : FileSystem.readDirectory(targetOutputDirectory.toString())
				.map(file -> new Path(FileSystem.fullPath(Path.join([targetOutputDirectory.toString(), file]))))
				.filter(fp -> libExtensions.indexOf(fp.ext) != -1)}
	}

	static function deployAsDependency(results:BuildResults) {
		if (config.verbose)
			trace('Deploying ${results.libs} as dependency');
		var outputDir = "bin";
		#if macro
		if (!Context.defined('anvil.output')) {
			final platform = Context.defined('hl') ? 'hl' : Context.defined('lua') ? 'lua' : Context.defined('cpp') ? 'cpp' : '';
			outputDir = 'bin\\$platform';
			if (config.verbose)
				Context.warning('-D anvil.output flag missing, outputting to default folder "$outputDir"', Context.currentPos());
		} else {
			outputDir = Context.definedValue('anvil.output');
		}
		#else
		// if()
		#end

		var fullOutputDir = Path.join([runningDirectory.toString(), outputDir]);
		if (!FileSystem.exists(fullOutputDir))
			FileSystem.createDirectory(fullOutputDir);
		copyLibsToPath(results, fullOutputDir);
	}

	static function deployToDirectory(results:BuildResults) {
		if (config.verbose)
			trace('Deploying ${results.libs} to ${config.deployInfo.dest}');
		copyLibsToPath(results, Path.join([runningDirectory.toString(), '${config.deployInfo.dest}']));
	}

	static function copyLibsToPath(results:BuildResults, deployPath) {
		for (lib in results.libs) {
			copyFile(new Path(FileSystem.fullPath(Path.join([lib.toString()]))),
				new Path(FileSystem.fullPath(Path.join([deployPath, lib.file.withExtension(lib.ext)]))));
		}
	}
}
