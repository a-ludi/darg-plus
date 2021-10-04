/**
    Functions and decorators that provide support for life cycle hooks.

    Copyright: © 2019 Arne Ludwig <arne.ludwig@posteo.de>
    License: Subject to the terms of the MIT license, as written in the
             included LICENSE file.
    Authors: Arne Ludwig <arne.ludwig@posteo.de>
*/
module darg_plus.hooks;


/**
    Decorate `Argument`s or `OptionFlag`s to declare validation procedures.
    Can be used multiple times per entity.

    Params:
        _validate = Performs required validations and throws if a validation
                    fails.
        isEnabled = This validation will have no effect if set to false.
*/
struct Validate(alias _validate, bool isEnabled = true) {
private:

    static if (isEnabled)
        alias validate = _validate;
    else
        alias validate = __noop;

    static void __noop(T)(T) { }
}


/**
    Decorate methods of the options struct to declare a hook that executes
    before all validations.
*/
struct PreValidate {
    /// Priority of execution. Higher priorities get executed first.
    Priority priority;
}


/**
    Decorate methods of the options struct to declare a hook that executes
    after all validations.
*/
struct PostValidate {
    /// Priority of execution. Higher priorities get executed first.
    Priority priority;
}


/**
    Decorate methods of the options struct to declare a hook that executes
    just before end of program execution.
*/
struct CleanUp {
    /// Priority of execution. Higher priorities get executed first.
    Priority priority;
}


/**
    Defines the priority of execution of a hook. Higher priorities get
    executed first.

    See_also:
        PreValidate, PostValidate
*/
struct Priority
{
    /// Pre-defined priorities provide good readbility and suffice in most
    /// cases.
    enum min = Priority(int.min);
    /// ditto
    enum low = Priority(-100);
    /// ditto
    enum medium = Priority(0);
    /// ditto
    enum high = Priority(100);
    /// ditto
    enum max = Priority(int.max);

    int priority;
    alias priority this;


    ///
    this(int priority) pure nothrow @safe @nogc
    {
        this.priority = priority;
    }


    /// Operator overloads give fine-grained control over priorities.
    Priority opBinary(string op)(int offset) const pure nothrow @safe @nogc
    {
        return mixin("Priority(priority "~op~" offset)");
    }


    /// ditto
    Priority opBinaryRight(string op)(int offset) const pure nothrow @safe @nogc
    {
        return mixin("Priority(offset "~op~" priority)");
    }
}

/// Operator overloads give fine-grained control over priorities.
unittest
{
    struct Options
    {
        @PreValidate(Priority.max)
        void initialPreparationStep1() { }

        @PreValidate(Priority.max - 1)
        void initialPreparationStep2() { }

        @PreValidate(Priority.medium)
        void hookSetDefaultValue() { }

        @PostValidate(Priority.medium)
        void hookCreateTmpdir() { }
    }
}

private template cmpPriority(T)
{
    enum cmpPriority(alias a, alias b) = getUDA!(a, T).priority > getUDA!(b, T).priority;
}

unittest
{
    struct Tester
    {
        @PostValidate(Priority.low)
        void priorityLow() { }

        @PostValidate(Priority.medium)
        void priorityMedium() { }

        @PostValidate(Priority.high)
        void priorityHigh() { }
    }

    alias compare = cmpPriority!PostValidate;

    static assert(compare!(
        Tester.priorityHigh,
        Tester.priorityLow,
    ));
    static assert(!compare!(
        Tester.priorityLow,
        Tester.priorityHigh,
    ));
    static assert(!compare!(
        Tester.priorityMedium,
        Tester.priorityMedium,
    ));
}


/// Call this method on the result of `parseArgs` to execute validations and
/// validation hooks.
Options processOptions(Options)(Options options)
{
    import darg :
        Argument,
        Option;
    import darg_plus.exception : CLIException;
    import std.format : format;
    import std.meta : staticSort;
    import std.string : wrap;
    import std.traits :
        getSymbolsByUDA,
        getUDAs;

    alias preValidateQueue = staticSort!(
        cmpPriority!PreValidate,
        getSymbolsByUDA!(Options, PreValidate),
    );

    static foreach (alias symbol; preValidateQueue)
    {
        mixin("options." ~ __traits(identifier, symbol) ~ "();");
    }

    static foreach (alias symbol; getSymbolsByUDA!(Options, Validate))
    {{
        alias validateUDAs = getUDAs!(symbol, Validate);

        foreach (validateUDA; validateUDAs)
        {
            alias validate = validateUDA.validate;
            auto value = __traits(getMember, options, __traits(identifier, symbol));
            alias Value = typeof(value);
            alias Validator = typeof(validate);

            try
            {
                static if (is(typeof(validate(value, options))))
                    cast(void) validate(value, options);
                else
                    cast(void) validate(value);
            }
            catch (Exception cause)
            {
                enum isOption = getUDAs!(symbol, Option).length > 0;
                enum isArgument = getUDAs!(symbol, Argument).length > 0;

                static if (isOption)
                {
                    enum thing = "option";
                    enum name = getUDAs!(symbol, Option)[0].toString();
                }
                else static if (isArgument)
                {
                    enum thing = "argument";
                    enum name = getUDAs!(symbol, Argument)[0].name;
                }
                else
                {
                    enum thing = "property";
                    enum name = __traits(identifier, symbol);
                }

                throw new CLIException("invalid " ~ thing ~ " " ~ name ~ ": " ~ cause.msg, cause);
            }
        }
    }}

    alias postValidateQueue = staticSort!(
        cmpPriority!PostValidate,
        getSymbolsByUDA!(Options, PostValidate),
    );

    static foreach (alias symbol; postValidateQueue)
    {
        mixin("options." ~ __traits(identifier, symbol) ~ "();");
    }

    return options;
}

///
unittest
{
    import std.exception :
        assertThrown,
        enforce;

    struct Tester
    {
        @Validate!(value => enforce(value == 1))
        int a = 1;

        @Validate!((value, options) => enforce(value == 2 * options.a))
        int b = 2;

        string[] calls;

        @PostValidate(Priority.low)
        void priorityLow() {
            calls ~= "priorityLow";
        }

        @PostValidate(Priority.medium)
        void priorityMedium() {
            calls ~= "priorityMedium";
        }

        @PostValidate(Priority.high)
        void priorityHigh() {
            calls ~= "priorityHigh";
        }
    }

    Tester options;

    options = processOptions(options);

    assert(options.calls == [
        "priorityHigh",
        "priorityMedium",
        "priorityLow",
    ]);

    options.a = 2;

    assertThrown!Exception(processOptions(options));
}


/// Call this method when your program is about to stop execution to enable
/// execution of `CleanUp` hooks.
///
/// Example:
/// ---
///
/// void main(in string[] args)
/// {
///     auto options = processOptions(parseArgs!Options(args[1 .. $]));
///
///     scope (exit) cast(void) cleanUp(options);
///
///     /// doing something productive ...
/// }
/// ---
Options cleanUp(Options)(Options options)
{
    import std.meta : staticSort;
    import std.traits : getSymbolsByUDA;

    alias cleanUpQueue = staticSort!(
        cmpPriority!CleanUp,
        getSymbolsByUDA!(Options, CleanUp),
    );

    static foreach (alias symbol; cleanUpQueue)
    {
        mixin("options." ~ __traits(identifier, symbol) ~ "();");
    }

    return options;
}

unittest
{
    import std.exception : assertThrown;

    struct Tester
    {
        string[] calls;

        @CleanUp(Priority.low)
        void priorityLow() {
            calls ~= "priorityLow";
        }

        @CleanUp(Priority.medium)
        void priorityMedium() {
            calls ~= "priorityMedium";
        }

        @CleanUp(Priority.high)
        void priorityHigh() {
            calls ~= "priorityHigh";
        }
    }

    Tester options;

    options = cleanUp(options);

    assert(options.calls == [
        "priorityHigh",
        "priorityMedium",
        "priorityLow",
    ]);
}

import std.traits : getUDAs;

private enum getUDA(alias symbol, T) = getUDAs!(symbol, T)[0];
