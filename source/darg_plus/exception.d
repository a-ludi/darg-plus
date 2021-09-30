/**
    Predefined exception classes for error hanlding.

    Copyright: © 2019 Arne Ludwig <arne.ludwig@posteo.de>
    License: Subject to the terms of the MIT license, as written in the
             included LICENSE file.
    Authors: Arne Ludwig <arne.ludwig@posteo.de>
*/
module darg_plus.exception;


/// Convenience class for errors during CLI parsing and processing.
class CLIException : Exception
{
    import std.exception : basicExceptionCtors;

    ///
    mixin basicExceptionCtors;
}


/// Convenience class for use with `--usage` flag.
class UsageRequested : CLIException
{
    import std.exception : basicExceptionCtors;

    ///
    mixin basicExceptionCtors;
}


/// Convenience class for use with `--version` flag.
class VersionRequested : CLIException
{
    import std.exception : basicExceptionCtors;

    ///
    mixin basicExceptionCtors;
}


/// Convenience class for use with `--usage` flag.
class ValidationError : CLIException
{
    import std.exception : basicExceptionCtors;

    ///
    mixin basicExceptionCtors;
}
