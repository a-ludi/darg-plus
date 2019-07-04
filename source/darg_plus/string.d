/**
    Functions that transform strings into values or vice versa.

    Copyright: © 2019 Arne Ludwig <arne.ludwig@posteo.de>
    License: Subject to the terms of the MIT license, as written in the
             included LICENSE file.
    Authors: Arne Ludwig <arne.ludwig@posteo.de>
*/
module darg_plus.string;


/**
    Parses a range in form `x..y` into a 2-element array.

    Params:
        dest        = Range limits are written to the aliased static array.
        DestType    = Allocate and return a static array of this type.
        msg         = Error message in case of failure.
        rangeString = The string to be parsed. The expected format is `x..y`.
*/
void parseRange(alias dest, string msg = "ill-formatted range")(in string rangeString) pure
        if (isStaticArray!(typeof(dest)) && dest.length == 2)
{
    try
    {
        rangeString[].formattedRead!"%d..%d"(dest[0], dest[1]);
    }
    catch (Exception e)
    {
        throw new CLIException(msg);
    }
}

/// ditto
DestType parseRange(DestType, string msg = "ill-formatted range")(in string rangeString) pure
        if (isStaticArray!DestType && DestType.init.length == 2)
{
    try
    {
        DestType dest;

        rangeString[].formattedRead!"%d..%d"(dest[0], dest[1]);

        return dest;
    }
    catch (Exception e)
    {
        throw new CLIException(msg);
    }
}

import std.traits : isFloatingPoint;

/**
    Convert a floating point number to a base-10 string at compile time.
    This function is very crude and will not work in many cases!
*/
string toString(Float)(in Float value, in uint precision) pure nothrow
    if (isFloatingPoint!Float)
{
    import std.conv : to;
    import std.math :
        ceil,
        floor,
        isInfinity,
        isNaN,
        round,
        sgn;

    if (value.isNaN)
        return "nan";
    else if (value.isInfinity)
        return value > 0 ? "inf" : "-inf";

    if (precision == 0)
    {
        auto intPart = cast(long) round(value);

        return intPart.to!string;
    }
    else
    {
        auto intPart = cast(long) (value > 0 ? floor(value) : ceil(value));
        auto fraction = sgn(value) * (value - intPart);
        assert(fraction >= 0, "fractional part of value should be non-negative");
        auto fracPart = cast(ulong) round(10^^precision * fraction);

        return intPart.to!string ~ "." ~ fracPart.to!string;
    }
}

///
unittest
{
    enum x = 42.0;
    enum y = -13.37f;
    enum z = 0.9;

    static assert(float.nan.toString(0) == "nan");
    static assert(double.infinity.toString(0) == "inf");
    static assert((-double.infinity).toString(0) == "-inf");
    static assert(x.toString(0) == "42");
    static assert(x.toString(1) == "42.0");
    static assert(y.toString(2) == "-13.37");
    static assert(y.toString(1) == "-13.4");
    static assert(y.toString(0) == "-13");
    static assert(z.toString(1) == "0.9");
    static assert(z.toString(0) == "1");
}
