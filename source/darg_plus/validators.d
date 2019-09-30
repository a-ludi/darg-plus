/**
    Validate and parse config files.

    Copyright: © 2019 Arne Ludwig <arne.ludwig@posteo.de>
    License: Subject to the terms of the MIT license, as written in the
             included LICENSE file.
    Authors: Arne Ludwig <arne.ludwig@posteo.de>
*/
module darg_plus.validators;


import darg_plus.exception : ValidationError;
static import std.exception;

/**
    General validation function.

    Params:
        value  = Value to be validated
        msg    = Error details in case of failure
    Throws:
        darg_plus.exception.ValidationError if `!isValid`.
*/
alias validate = std.exception.enforce!ValidationError;

/**
    Validates that value is positive.

    Params:
        value  = Value to be validated
        msg    = Error details in case of failure
    Throws:
        darg_plus.exception.ValidationError
            if value is less than or equal to zero.
    See_also:
        validate
*/
void validatePositive(V)(V value, lazy string msg = "must be greater than zero")
{
    validate(0 < value, msg);
}

/**
    Validates that the values described by rangeString are non-negative and
    in ascending order. Validation is skipped if rangeString is `null`.

    Params:
        rangeString  = Range to be validated
        msg    = Error details in case of failure
    Throws:
        darg_plus.exception.ValidationError
            unless rangeString is `null` or `0 <= x && x < y`.
    See_also:
        validate
*/
void validateRangeNonNegativeAscending(DestType)(
    in string rangeString,
    lazy string msg = "0 <= <from> < <to> must hold",
)
{
    if (rangeString !is null)
    {
        import darg_plus.string : parseRange;

        auto rangeBounds = parseRange!DestType(rangeString);
        auto from = rangeBounds[0];
        auto to = rangeBounds[1];

        validate(0 <= from && from < to, msg);
    }
}


import std.range.primitives : isInputRange;

/**
    Validates that the files exist.

    Params:
        file  = File name of the file to be tested.
        files = File names of the files to be tested.
        msg    = Error details in case of failure
    Throws:
        darg_plus.exception.ValidationError
            unless rangeString is `null` or `0 <= x && x < y`.
    See_also:
        validate, std.file.exists
*/
void validateFilesExist(R)(R files, lazy string msg = "cannot open file `%s`") if (isInputRange!R)
{
    foreach (file; files)
        validateFileExists(file, msg);
}

/// ditto
void validateFileExists(S)(in S file, lazy string msg = "cannot open file `%s`")
{
    import std.file : exists;
    import std.format : format;

    validate(file.exists, format(msg, file));
}


import std.meta :
    allSatisfy,
    staticMap;
import std.traits : isSomeString;

/**
    Validates that the file has one of the allowed extensions.

    Params:
        extensions  = Allowed extensions including a leading dot.
        file        = File name of the file to be tested.
        msg    = Error details in case of failure
    Throws:
        darg_plus.exception.ValidationError
            if the extension of file is not in the list of allowed extensions.
    See_also:
        validate, std.algorithm.searching.endsWith
*/
void validateFileExtension(extensions...)(
    in string file,
    lazy string msg = "invalid file extension: expected one of %-(%s, %) but got %s",
)
        if (allSatisfy!(isSomeString, staticMap!(typeOf, extensions)))
{
    import std.algorithm : endsWith;
    import std.format : format;

    validate(file.endsWith(extensions), format(msg, [extensions], file));
}

private alias typeOf(alias T) = typeof(T);

/**
    Validates that the file is writable.

    Params:
        file        = File name of the file to be tested.
        msg    = Error details in case of failure
    Throws:
        darg_plus.exception.ValidationError
            if file cannot be opened for writing.
    See_also:
        validate, std.algorithm.searching.endsWith
*/
void validateFileWritable(string file, lazy string msg = "cannot open file `%s` for writing: %s")
{
    import std.exception : ErrnoException;
    import std.file :
        exists,
        remove;
    import std.format : format;
    import std.stdio : File;

    auto deleteAfterwards = !file.exists;

    scope (exit)
        if (deleteAfterwards)
            remove(file);

    try
    {
        cast(void) File(file, "a");
    }
    catch (ErrnoException e)
    {
        validate(false, format(msg, file, e.msg));
    }

}
