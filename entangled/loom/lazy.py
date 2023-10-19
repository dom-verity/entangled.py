"""
Module `entangled.loom.lazy` presents us with a `Lazy` tasks that have
targets and a set of dependencies. A `Task` will have an abstract
method `run`. Then the purpose is to run those tasks in correct
order and possibly in parallel.

This is achieved by memoizing results and keeping locks on the `Lazy`
task when it is still evaluating.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Generic, Optional, TypeVar, Union
import asyncio

from ..errors.user import UserError


T = TypeVar("T")
R = TypeVar("R")


@dataclass
class Failure(Generic[T]):
    task: T

    def __bool__(self):
        return False


class MissingFailure(Failure[T]):
    pass


@dataclass
class TaskFailure(Failure[T], Exception):
    message: str

    def __post_init__(self):
        Exception.__init__(self, self.message)


@dataclass
class DependencyFailure(Failure[T], Generic[T]):
    dependent: list[Failure[T]]


@dataclass
class Ok(Generic[T, R]):
    task: Lazy[T, R]
    value: R

    def __bool__(self):
        return True


Result = Union[Failure, Ok[T, R]]


@dataclass
class Lazy(Generic[T, R]):
    """Base class for tasks that are tagged with type `T` (usually `str` or
    `Path`) and representing values of type `R`.

    To implement a specific task, you need to implement the asynchronous
    `run` method, which should return a value of `R` or throw `TaskFailure`.

    Attributes:
        targets: list of target identifiers, for instance paths that are
            generated by running a particular task.
        dependencies: list of dependency identifiers. All of these need to
            be realized before the task can run.
        result (property): value of the result, once the task was run. This
            throws an exception if accessed before the task is complete.
    """

    targets: list[T]
    dependencies: list[T]
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock, init=False)
    _result: Optional[Result[T, R]] = field(default=None, init=False)

    def __bool__(self):
        return self._result is not None and bool(self._result)

    @property
    def result(self) -> R:
        if self._result is None:
            raise ValueError("Task has not run yet.")
        if not self._result:
            raise ValueError("Task has failed.")
        assert isinstance(self._result, Ok)
        return self._result.value

    async def run(self) -> R:
        raise NotImplementedError()

    async def run_after_deps(self, recurse, *args) -> Result[T, R]:
        dep_res = await asyncio.gather(*(recurse(dep) for dep in self.dependencies))
        if not all(dep_res):
            return DependencyFailure(self, [f for f in dep_res if not f])
        try:
            result = await self.run(*args)
            return Ok(self, result)
        except TaskFailure as f:
            return f

    async def run_cached(self, recurse, *args) -> Result[T, R]:
        async with self._lock:
            if self._result is not None:
                return self._result
            self._result = await self.run_after_deps(recurse, *args)
            return self._result

    def reset(self):
        self._result = None


TaskT = TypeVar("TaskT", bound=Lazy)


class MissingDependency(Exception):
    pass


@dataclass
class LazyDB(Generic[T, TaskT]):
    """Collect tasks and coordinate running a task from a task identifier."""

    tasks: list[TaskT] = field(default_factory=list)
    index: dict[T, TaskT] = field(default_factory=dict)

    async def run(self, t: T, *args) -> Result[T, R]:
        if t not in self.index:
            try:
                task = self.on_missing(t)
            except MissingDependency:
                return MissingFailure(t)
        else:
            task = self.index[t]
        return await task.run_cached(self.run, *args)

    def on_missing(self, _: T) -> TaskT:
        raise MissingDependency()

    def add(self, task: TaskT):
        """Add a task to the DB."""
        self.tasks.append(task)
        for target in task.targets:
            self.index[target] = task

    def clean(self):
        self.tasks = []
        self.index = {}

    def reset(self):
        for t in self.tasks:
            t.reset()
