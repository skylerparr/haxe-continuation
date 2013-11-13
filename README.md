haxe-continuation
=================

This is a fork of haxe-continuation with an improved Haxe 3.0 syntax, and several new features.

**haxe-continuation** works with asynchronous functions, written in *continuation-passing style (CPS)*. In CPS, 
instead of a function returning a result, it takes a callback function as a parameter, which will be invoked when 
the operation is complete. For example, an asynchronous function that loads a file might look like:

    function loadFile(name:String, results:String->Void) : Void

To use this function to load two files, one after the other, you might write something like this:

    loadFile("one.txt", function(contentsOne) {
      loadFile("two.txt", function(contentsTwo) {
        trace("both files loaded!");
      });
    });

CPS has recently been popularized by server frameworks like node.js. One of the downsides of CPS is that the number of
anonymous callback functions can get very deep, making for very hard to read code. Additionally, doing things like
asynchronously iterating over a list of objects is hard to write and error-prone. 

**haxe-continuation** allows you to write the preceding code like so:

    var contentsOne = @await loadFile("one.txt");
    var contentsTwo = @await loadFile("two.txt");
    trace("both files loaded!");

The Haxe macro system is used to transform the code to CPS at compile time, making it easier for you to write asynchronous 
code, while inflicting no additional runtime overhead. It is designed in particular for making it easier to write node.js code.

## Installation

Type the following command in your shell:

    haxelib git continuation https://github.com/proletariatgames/haxe-continuation.git

Now you can use continuation in your code:

Output to JavaScript:

    haxe -lib continuation -main Your.hx -js your-output.js

, or output to SWF:

    haxe -lib continuation -main Your.hx -swf your-output.swf

, or output to any other platform that Haxe supports.

This fork of haxe-continuation requires Haxe 3.0.

## Usage

You can create a class that supports asynchronous methods by implementing the Async interface. This interface has no
methods to implement - it simply instructs the compiler to invoke the code transformation. To write an async function,
add the @async metadata. An async function can then use @await to invoke another async function. Example:


    import com.dongxiguo.continuation.Async;
    class Sample implements Async
    {
      @async function concatFileContents(fileOne:String, fileTwo:String) : String {
        var contentsOne = @await loadFile(fileOne);
        var contentsTwo = @await loadFile(fileTwo);
        return contentsOne + contentsTwo;
      }
    }

This code is transformed at compile time to something like the following:

    class Sample
    {
      function concatFileContents(fileOne:String, fileTwo:String, __result:String->Void) : Void {
        loadFile(fileOne, function(contentsOne) {
          loadFile(fileTwo, function(contentsTwo) {
            __result(contentsOne + contentsTwo);
          });
        });
      }
    }

Another feature in **haxe-continuation** is *forking*. The analogy to multithreaded code is instead of processing a list of items
serially (one after the other), you start a thread for each item, and wait for all threads to return. This can increase
performance by issuing several blocking calls at once, and serving each one as soon as the results are available. 

An example fork:

    import com.dongxiguo.continuation.Async;
    class Sample implements Async
    {
      @async function concatFilesInAnyOrder(files:Array<String>) : String {
        var output = "";
        // start a separate "thread" for each element in the array
        @fork(file in files) {
          // the code block executed by each "thread"
          output += @await loadFile(file);
        }
        // at this point, all threads have finished executing.
        return output;
      }
    }

Note that in the preceding example, the loadFile callbacks may be executed in any order, so the returned contents
might not be in the same order as the input array.

Finally, some libraries such as node.js may return several outputs in their CPS functions, for example:

    function loadFileWithError(file:String, result:ErrorCode->String->Void) : Void;

In this case, the callback function returns both an error code and the file contents. You can get both results using
@await like so:

    var error, contents = @await loadFileWithError("file.txt");

### Working with [hx-node](https://github.com/cloudshift/hx-node)

Look at https://github.com/proletariatgames/haxe-continuation/blob/master/tests/TestNode.hx
The example forks 5 threads, and calls Node.js's asynchronous functions in each thread.

## License

Copyright (c) 2012, 杨博 (Yang Bo)
All rights reserved.

Author: 杨博 (Yang Bo) <pop.atry@gmail.com>

Contributor: Dan Ogles <dan@proletariat.com>

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
* Neither the name of Proletariat, Inc. nor the names of its contributors
  may be used to endorse or promote products derived from this software
  without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
