/**
    Validate and parse config files.

    Copyright: © 2019 Arne Ludwig <arne.ludwig@posteo.de>
    License: Subject to the terms of the MIT license, as written in the
             included LICENSE file.
    Authors: Arne Ludwig <arne.ludwig@posteo.de>
*/
module darg_plus.configfile;

import darg :
    Argument,
    isArgumentHandler,
    isOptionHandler,
    Option,
    OptionFlag;
import vibe.data.json : Json;

///
unittest
{
    import darg : Multiplicity;
    import vibe.data.json;

    auto config = serializeToJson([
        "file": Json("/path/to/file"),
        "more_files": serializeToJson([
            "/path/to/file1",
            "/path/to/file2",
        ]),
        "num": Json(42),
        "verbose": Json(true),
    ]);

    struct Options
    {
        @Argument("<in:file>")
        string file;

        @Argument("<in:more_files>", Multiplicity.zeroOrMore)
        string[] moreFiles;

        @Option("num")
        size_t num;

        @Option("verbose")
        OptionFlag verbose;
    }

    auto options = parseConfig!Options(config);

    assert(options.file == "/path/to/file");
    assert(options.moreFiles == [
        "/path/to/file1",
        "/path/to/file2",
    ]);
    assert(options.num == 42);
    assert(options.verbose == true);
}

///
unittest
{
    import vibe.data.json;

    auto config = serializeToJson([
        "file": Json("/path/to/file"),
        "num": Json(42),
    ]);

    struct Options
    {
        @Argument("<in:file>")
        string file;

        @Option("num")
        size_t num = 1337;
    }

    Options options;

    // Config values override default option values and arguments that are
    // marked as empty:
    options.file = configEmptyArgument;
    assert(options.num == 1337);

    options = retroInitFromConfig(options, config);

    assert(options.file == "/path/to/file");
    assert(options.num == 42);

    // Modified values, ie. given on the CLI, have precedence
    // over config values:
    options.file = "/path/from/cli";
    options.num = 13;

    assert(options.file == "/path/from/cli");
    assert(options.num == 13);
}

/// String-type values equal to this string are considered empty.
enum configEmptyArgument = "-";

/// Keys prefixed with this string are ignored.
enum configCommentPrefix = "//";

/// Maximum size of a valid config file.
enum maxConfigSize = toBytes(256, SizeUnit.MiB);


/// Thrown if an error while handling config file occurs.
class ConfigFileException : Exception
{
    string configKey;
    Json configValue;

    /**
        Params:
            msg  = The message for the exception.
            next = The previous exception in the chain of exceptions.
            file = The file where the exception occurred.
            line = The line number where the exception occurred.
    */
    this(string msg, Throwable next, string file = __FILE__,
         size_t line = __LINE__) @nogc @safe pure nothrow
    {
        super(msg, file, line, next);
    }

    /**
        Params:
            msg         = The message for the exception.
            configKey   = Key of the erroneous config entry.
            configValue = Value of the erroneous config entry.
            file        = The file where the exception occurred.
            line        = The line number where the exception occurred.
            next        = The previous exception in the chain of exceptions, if any.
    */
    this(string msg, string configKey, Json configValue = Json.init, string file = __FILE__, size_t line = __LINE__,
         Throwable next = null) @nogc @safe pure nothrow
    {
        super(msg, file, line, next);
        this.configKey = configKey;
        this.configValue = configValue;
    }

    /**
        Params:
            msg         = The message for the exception.
            configKey   = Key of the erroneous config entry.
            configValue = Value of the erroneous config entry.
            next        = The previous exception in the chain of exceptions.
            file        = The file where the exception occurred.
            line        = The line number where the exception occurred.
    */
    this(string msg, string configKey, Json configValue, Throwable next, string file = __FILE__,
         size_t line = __LINE__) @nogc @safe pure nothrow
    {
        super(msg, file, line, next);
        this.configKey = configKey;
        this.configValue = configValue;
    }
}

T enforce(T)(
    T value,
    lazy string message,
    lazy string configKey = null,
    lazy Json configValue = Json.init,
    string file = __FILE__,
    size_t line = __LINE__,
)
{
    static import std.exception;

    return std.exception.enforce(value, new ConfigFileException(
        message,
        configKey,
        configValue,
        file,
        line,
    ));
}


/// Retroactively initialize options from config.
Options retroInitFromConfig(Options)(ref Options options, in string configFile)
{
    return retroInitFromConfig(options, parseConfig!Options(configFile));
}

/// ditto
Options retroInitFromConfig(Options)(ref Options options, in Json config)
{
    return retroInitFromConfig(options, parseConfig!Options(config));
}

/// ditto
Options retroInitFromConfig(Options)(ref Options options, Options optionsFromConfig)
{
    import std.algorithm : all;
    import std.format : format;
    import std.math : isNaN;
    import std.meta : Alias;
    import std.range.primitives : ElementType;
    import std.traits :
        getUDAs,
        isArray,
        isFloatingPoint,
        isSomeString,
        isSomeString,
        isStaticArray;

    enum defaultOptions = Options.init;

    static foreach (member; __traits(allMembers, Options))
    {{
        alias symbol = Alias!(__traits(getMember, options, member));
        enum isMemberAssignable = __traits(compiles,
            __traits(getMember, options, member) = __traits(getMember, options, member)
        );

        static if (isMemberAssignable)
        {
            alias Member = typeof(__traits(getMember, options, member));
            enum unaryMixin(string template_) = format!template_(member);
            enum binaryMixin(string template_) = format!template_(member, member);
            alias assignConfigValue = () => mixin(binaryMixin!"options.%s = optionsFromConfig.%s");

            static if (getUDAs!(symbol, Argument).length > 0)
            {
                static if (isSomeString!Member)
                {
                    if (mixin(unaryMixin!"options.%s == configEmptyArgument"))
                        assignConfigValue();
                }
                else static if (isArray!Member && isSomeString!(ElementType!Member))
                {
                    if (mixin(unaryMixin!"options.%s.all!(v => v == configEmptyArgument)"))
                        assignConfigValue();
                }
            }
            else
            {
                static if (isStaticArray!Member || is(Member == class))
                {
                    if (mixin(binaryMixin!"options.%s == defaultOptions.%s"))
                        assignConfigValue();
                }
                else static if (isFloatingPoint!Member)
                {
                    if (
                        mixin(binaryMixin!"options.%s == defaultOptions.%s") ||
                        (
                            mixin(unaryMixin!"options.%s.isNaN") &&
                            mixin(unaryMixin!"defaultOptions.%s.isNaN")
                        )
                    )
                        assignConfigValue();
                }
                else
                {
                    if (mixin(binaryMixin!"options.%s is defaultOptions.%s"))
                        assignConfigValue();
                }
            }
        }
    }}

    return options;
}


/// Initialize options using config.
Options parseConfig(Options)(in string configFile)
{
    import vibe.data.json : parseJson;

    auto configContent = readConfigFile(configFile);
    auto configValues = parseJson(
        configContent,
        null,
        configFile,
    );

    return parseConfig!Options(configValues);
}

/// ditto
Options parseConfig(Options)(in Json config)
{
    import std.meta : Alias;

    validateConfig!Options(config);

    Options options;

    foreach (member; __traits(allMembers, Options))
    {
        alias symbol = Alias!(__traits(getMember, options, member));
        enum names = configNamesOf!symbol;

        static if (names.length > 0)
        {
            foreach (name; names)
                if (name in config)
                    options.assignConfigValue!member(name, config[name]);
        }
    }

    return options;
}

/// Validate config.
void validateConfigFile(Options)(in string configFile)
{
    import vibe.data.json : parseJson;

    auto configContent = readConfigFile(configFile);
    auto configValues = parseJson(
        configContent,
        null,
        configFile,
    );

    validateConfig!Options(configValues);
}

/// ditto
void validateConfig(Options)(in Json config)
{
    import std.algorithm : startsWith;
    import std.format : format;
    import std.meta : Alias;

    enforce(config.type == Json.Type.object, "config must contain a single object");

    configLoop: foreach (configKey, configValue; config.byKeyValue)
    {
        if (configKey.startsWith(configCommentPrefix))
            continue;

        foreach (member; __traits(allMembers, Options))
        {
            alias symbol = Alias!(__traits(getMember, Options, member));
            enum names = configNamesOf!symbol;

            static if (names.length > 0)
            {
                alias SymbolType = typeof(__traits(getMember, Options, member));

                foreach (name; names)
                {
                    try
                    {
                        if (name == configKey)
                        {
                            cast(void) getConfigValue!SymbolType(configKey, configValue);
                            continue configLoop;
                        }
                    }
                    catch (Exception cause)
                    {
                        throw new ConfigFileException(
                            format!"malformed config value `%s`: %s"(
                                configKey,
                                cause.msg,
                            ),
                            configKey,
                            configValue,
                            cause,
                        );
                    }
                }
            }
        }

        throw new ConfigFileException(
            format!"invalid config key `%s`"(
                configKey,
            ),
            configKey,
        );
    }
}

template configNamesOf(alias symbol)
{
    import std.array : split;
    import std.traits : getUDAs;

    alias optUDAs = getUDAs!(symbol, Option);
    alias argUDAs = getUDAs!(symbol, Argument);

    static if (argUDAs.length > 0)
        enum argName = argUDAs[0].name.split(":")[$ - 1][0 .. $ - 1];

    static if (optUDAs.length > 0 && argUDAs.length > 0)
    {
        enum configNamesOf = optUDAs[0].names ~ argName;
    }
    else static if (optUDAs.length > 0)
    {
        enum configNamesOf = optUDAs[0].names;
    }
    else static if (argUDAs.length > 0)
    {
        enum configNamesOf = [argName];
    }
    else
    {
        enum string[] configNamesOf = [];
    }
}

void assignConfigValue(string member, Options)(ref Options options, string configKey, Json configValue)
{
    import std.conv : to;
    import std.traits : isAssignable;

    alias SymbolType = typeof(__traits(getMember, options, member));

    static if (isOptionHandler!SymbolType)
    {
        if (configValue.type == Json.Type.int_)
            foreach (i; 0 .. configValue.get!ulong)
                __traits(getMember, options, member)();
        else if (configValue.type == Json.Type.bool_)
        {
            if (configValue.get!bool)
                __traits(getMember, options, member)();
        }
        else
            throw new ConfigFileException(
                "Got JSON of type " ~ configValue.type.to!string ~
                ", expected int_ or bool_.",
                configKey,
                configValue,
            );
    }
    else static if (isArgumentHandler!SymbolType)
    {
        if (configValue.type == Json.Type.array)
            foreach (item; configValue.get!(Json[]))
                __traits(getMember, options, member)(item.get!string);
        else if (configValue.type == Json.Type.string)
            __traits(getMember, options, member)(configValue.get!string);
        else
            throw new ConfigFileException(
                "Got JSON of type " ~ configValue.type.to!string ~
                ", expected array or string_.",
                configKey,
                configValue,
            );
    }
    else static if (isAssignable!SymbolType)
    {
        __traits(getMember, options, member) = getConfigValue!SymbolType(configKey, configValue);
    }
}

auto getConfigValue(SymbolType)(string configKey, Json configValue)
{
    import std.conv : to;
    import std.range.primitives : ElementType;
    import std.traits :
        isArray,
        isDynamicArray,
        isFloatingPoint,
        isIntegral,
        isSomeString,
        isUnsigned;

    static if (is(SymbolType == OptionFlag))
        return configValue.get!bool.to!SymbolType;
    else static if (is(SymbolType == enum))
        return configValue.get!string.to!SymbolType;
    else static if (is(SymbolType == OptionFlag) || is(SymbolType : bool))
        return configValue.get!bool.to!SymbolType;
    else static if (isFloatingPoint!SymbolType)
        return configValue.get!double.to!SymbolType;
    else static if (isIntegral!SymbolType && isUnsigned!SymbolType)
        return configValue.get!ulong.to!SymbolType;
    else static if (isIntegral!SymbolType && !isUnsigned!SymbolType)
        return configValue.get!long.to!SymbolType;
    else static if (isSomeString!SymbolType)
    {
        if (configValue.type == Json.Type.string)
            return configValue.get!string.to!SymbolType;
        else if (configValue.type == Json.Type.null_)
            return null;
        else
            throw new ConfigFileException(
                "Got JSON of type " ~ configValue.type.to!string ~
                ", expected string or null_.",
                configKey,
                configValue,
            );
    }
    else static if (isArray!SymbolType)
    {
        SymbolType value;

        static if (isDynamicArray!SymbolType)
            value.length = configValue.length;
        else
            enforce(
                configValue.length == value.length,
                "array must have " ~ value.length ~ " elements",
                configKey,
                configValue,
            );

        foreach (size_t i, configElement; configValue.get!(Json[]))
            value[i] = getConfigValue!(ElementType!SymbolType)(configKey, configElement);

        return value;
    }
}

string readConfigFile(in string configFileName)
{
    import std.stdio : File;
    import std.format : format;

    auto configFile = File(configFileName, "r");
    auto configFileSize = configFile.size;

    enforce(
        configFileSize <= maxConfigSize,
        format!"config file is too large; must be <= %.2f %s"(fromBytes(maxConfigSize).expand),
    );

    auto configContent = configFile.rawRead(new char[configFileSize]);

    return cast(string) configContent;
}

/// Units for bytes.
enum SizeUnit
{
    B,
    KiB,
    MiB,
    GiB,
    TiB,
    PiB,
    EiB,
    ZiB,
    YiB,
}

/// Convert a value and unit to number of bytes.
auto toBytes(in size_t value, in SizeUnit unit)
{
    return value * sizeUnitBase^^unit;
}

/// Convert bytes to
auto fromBytes(in size_t bytes)
{
    import std.conv : to;
    import std.typecons : tuple;
    import std.traits : EnumMembers;

    alias convertToUnit = exp => tuple!("value", "unit")(
        bytes.to!double / (sizeUnitBase^^exp),
        exp,
    );

    foreach (exp; EnumMembers!SizeUnit)
    {
        if (bytes <= sizeUnitBase^^exp)
            return convertToUnit(exp);
    }

    return convertToUnit(SizeUnit.max);
}

private enum size_t sizeUnitBase = 2^^10;
