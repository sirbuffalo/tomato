class TomatoError(Exception):
    """A compile-time or run-time error in a Tomato program."""

    def __init__(self, message, line=None):
        self.message = message
        self.line = line
        super().__init__(message if line is None else "line %d: %s" % (line, message))


class NotDecided(TomatoError):
    """The language rule needed here has not been decided yet."""

    def __init__(self, message, line=None):
        super().__init__("not yet decided: " + message, line)


class RunFailure(TomatoError):
    """A run-time failure a program can catch with try/catch (D22a). `kind` names the Tomato error class."""

    def __init__(self, message, line=None, kind="RuntimeError"):
        self.kind = kind
        super().__init__(message, line)


class TomatoRaise(Exception):
    """A Tomato error value raised by `raise`, travelling up to a matching catch."""

    def __init__(self, value, line=None):
        self.value, self.line = value, line
        super().__init__("raised")
