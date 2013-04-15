package com.dongxiguo.continuation;

enum TaskStatus<T> {
  Running;
  Stalled(task:Task<Dynamic>);
  Returned(value:T);
  Exception(exception:Dynamic);
}

class TaskInterruption {
  public function new() {}
}

class Task<T>
{
  public var status(default, null) : TaskStatus<T>;
  public var result(get_result, never) : T;
  public var running(get_running, never) : Bool;
  public var completion:Void->Void;

  public function new() {
  }

  public static inline function immediate<T>(value:T) : Task<T> {
    return new Task().run(function(__return){
      __return(value);
    });
  }

  public static inline function wrap<T>(cps:(T->Void)->Void) : Task<T> {
    return new Task().run(cps);
  }

  public static inline function wrap0(cps:(Void->Void)->Void) : Task<Void> {
    return new Task().run0(cps);
  }

  function run0(op:(Void->Void)->Void) : Task<Void> {
    status = Running;
    try {
      op(function() {
        status = Returned(null);
        callCompletion();
      });
    } catch ( e:Dynamic ) {
      handleException(e);
    }
    if ( status == null ) throw "Invalid status after starting task";
    return cast this;
  }

  public function run(op:(T->Void)->Void) : Task<T> {
    status = Running;
    try {
      op(function(result) {
        status = Returned(result);
        callCompletion();
      });
    } catch ( e:Dynamic ) {
      handleException(e);
    }
    if ( status == null ) throw "Invalid status after starting task";
    return this;
  }

  public function onCompletion(completion:Void->Void) : Void {
    switch ( status ) {
    case Returned(_), Exception(_): completion();
    case Stalled(_), Running: this.completion = completion;
    }
  }

  public function then(parent:Task<Dynamic>, next:T->Void) : Void {
    switch ( this.status ) {
    case Returned(_), Stalled(_), Running:
      parent.status = Stalled(this);
      this.onCompletion(function() {
        switch ( parent.status ) {
        case Stalled(_):
          switch ( this.status ) {
          case Returned(f):
            parent.status = Running;
            try {
              next(f);
            } catch ( e:Dynamic ) {
              parent.handleException(e);
            }
          case Exception(e):
            parent.handleException(e);
          case Stalled(_), Running: throw "Resume called, but task is still running";
          }
        case Exception(_): // task threw an exception while we were waiting on subtask; do not attempt to continue
        case Running: "Resume called, but parent task is already running";
        case Returned(_): "Cannot call completion twice on task";
        }
      });
    case Exception(e):
      parent.handleException(e);
    }
  }

  public function then0(parent:Task<Dynamic>, next:Void->Void) : Void {
    switch ( this.status ) {
    case Returned(_), Stalled(_), Running:
      parent.status = Stalled(this);
      this.onCompletion(function() {
        switch ( parent.status ) {
        case Stalled(_):
          switch ( this.status ) {
          case Returned(_):
            parent.status = Running;
            try {
              next();
            } catch ( e:Dynamic ) {
              parent.handleException(e);
            }
          case Exception(e):
            parent.handleException(e);
          case Stalled(_), Running: throw "Resume called, but task is still running";
          }
        case Exception(_): // task threw an exception while we were waiting on subtask; do not attempt to continue
        case Running: "Resume called, but parent task is already running";
        case Returned(_): "Cannot call completion twice on task";
        }
      });
    case Exception(e):
      parent.handleException(e);
    }
  }

  public inline function interrupt() : Void {
    switch ( status ) {
    case Returned(_), Exception(_): // do nothing
    case Stalled(t): t.interrupt(); // this will interrupt the subtask, which will interrupt us.
    case Running: interruption();
    }
  }

  function interruption() : Void {
    throw new TaskInterruption();
  }

  inline function get_result() : T {
    switch ( status ) {
    case Returned(v): return v;
    case Exception(e): throw e; null;
    case Stalled(_), Running: throw "Task still running!"; null;
    }
  }

  inline function get_running() : Bool {
    return switch ( status ) {
    case Returned(_), Exception(_): false;
    default: true;
    }
  }

  inline function handleException(e:Dynamic) : Void {
    this.status = Exception(e);
    callCompletion();
  }

  inline function callCompletion() : Void {
    if ( this.running ) throw "attempting to call completion while task is still running";
    if ( completion != null ) {
      var c = completion;
      completion = null;
      c();
    }
  }
}

/*
function z(a:Int, b:Int) : Task<Int> {
  var __task = new Task();
  return __task.run(function(__return:Int->Void) : Void {
    foo().then(__task, function(x) {
      bar(x).then(__task, function(y) {
        Task.wrapCPS(zed.bind(x, y)).then(__task, function(z) {
           
        });
        trace(x);
        __return(1);
      });
    });
  }
}
*/
