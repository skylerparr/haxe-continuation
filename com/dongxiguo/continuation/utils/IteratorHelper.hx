package com.dongxiguo.continuation.utils;

@:forward
abstract IteratorHelper<T>(Iterator<T>) from Iterator<T> {
  @:from inline public static function fromIterable<T>(iterable:Iterable<T>):IteratorHelper<T> {
    return iterable.iterator();
  }

  inline public static function get<T>(i:IteratorHelper<T>):Iterator<T> {
    return i.underlying();
  }

  inline public function underlying():Iterator<T> return this;
}
