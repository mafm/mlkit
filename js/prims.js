CompilerInitial = {}

CompilerInitial.en$Bind$42 = new String("Bind");
CompilerInitial.exn$Bind$42 = Array(CompilerInitial.en$Bind$42);
CompilerInitial.en$Match$41 = new String("Match");
CompilerInitial.exn$Match$41 = Array(CompilerInitial.en$Match$41);
CompilerInitial.en$Div$40 = new String("Div");
CompilerInitial.exn$Div$40 = Array(CompilerInitial.en$Div$40);
CompilerInitial.en$Interrupt = new String("Interrupt");
CompilerInitial.exn$Interrupt = Array(CompilerInitial.en$Interrupt);
CompilerInitial.en$Overflow$43 = new String("Overflow");
CompilerInitial.exn$Overflow$43 = Array(CompilerInitial.en$Overflow$43);

SmlPrims = {}

SmlPrims.option = function(e) {
  if ( e ) {
    return Array("SOME",e);
  } else {
    return Array("NONE");
  }
}

SmlPrims.explode = function(s) {
  var i;
  var res = Array("nil");
  for ( i = s.length ; i > 0 ; i-- ) {
    res = Array("::",Array(s.charCodeAt(i-1),res));
  }
  return res;
}

SmlPrims.implode = function(xs) {
  var i;
  var a = Array();
  for ( i = 0 ; xs[0] != "nil" ; xs = xs[1][1], i++ ) {
    a[i] = String.fromCharCode(xs[1][0]);
  }
  return a.join("");
}

SmlPrims.charsToCharArray = function(xs) {
  var i;
  var a = Array();
  for ( i = 0 ; xs[0] != "nil" ; xs = xs[1][1], i++ ) {
    a[i] = xs[1][0];
  }
  return a;
}

SmlPrims.listToArray = function(xs) {
  var i;
  var a = Array();
  for ( i = 0 ; xs[0] != "nil" ; xs = xs[1][1], i++ ) {
    a[i] = xs[1][0];
  }
  return a;
}

SmlPrims.charArraysConcat = function(xs) {
  var i;
  var a = Array();
  for ( i = 0 ; xs[0] != "nil" ; xs = xs[1][1], i++ ) {
    a = Array.concat(a, xs[1][0]);
  }
  return a;
}

SmlPrims.concat = function(xs) {
  var i;
  var a = Array();
  for ( i = 0 ; xs[0] != "nil" ; xs = xs[1][1], i++ ) {
    a[i] = xs[1][0];
  }
  return a.join("");
}

SmlPrims.length = function len(a) {
  switch(a[0]) {
    case "nil": return 0; break;
    default: return(1 + len(a[1][1]));
  }
}

SmlPrims.arrayMap = function(f) { 
    return function(a) {
        var i;
        var a2 = Array(a.length);
        for (i = 0; i < a.length; i++ ) {
          a2[i] = f(a[i]);
        };
        return a2;
    };
}

SmlPrims.charArrayToString = function(a) {
 var a2 = SmlPrims.arrayMap(String.fromCharCode)(a);
 return a2.join("");
}

SmlPrims.wordTableInit = function(n,x) {
  var i;
  var a = Array(n);
  for ( i = 0 ; i < n ; i++) {
    a[i] = x;
  };
  return a;
}

SmlPrims.chk_ovf_i32 = function (i) {
  if ( i < -2147483648 || i > 2147483647 ) {
    throw(CompilerInitial.exn$Overflow$43);
  }
  return i;
}

SmlPrims.chk_ovf_i31 = function (i) {
  if ( i < -1073741824 || i > 1073741823 ) {
    throw(CompilerInitial.exn$Overflow$43);
  }
  return i;
}

SmlPrims.cut_w32 = function (w) {
  return w & 0xFFFFFFFF;
}

SmlPrims.cut_w31 = function (w) {
  return w & 0x7FFFFFFF;
}

SmlPrims.mod_i32 = function (x,y,exn) {
  if ( y == 0 ) { throw(exn); }
  if ( (x > 0 && y > 0) || (x < 0 && y < 0) || (x % y == 0) ) {
    return x % y;
  }
  return (x % y) + y;
}

SmlPrims.div_i32 = function (x,y,exn) {
  if ( y == 0 ) { throw(exn); }
  if ( y == -1 && x == -2147483648 ) { throw(CompilerInitial.exn$Overflow$43); }
  return Math.floor(x / y);
}

SmlPrims.mod_i31 = function (x,y,exn) {
  if ( y == 0 ) { throw(exn); }
  if ( (x > 0 && y > 0) || (x < 0 && y < 0) || (x % y == 0) ) {
    return x % y;
  }
  return (x % y) + y;
}

SmlPrims.div_i31 = function (x,y,exn) {
  if ( y == 0 ) { throw(exn); }
  if ( y == -1 && x == -1073741824 ) { throw(CompilerInitial.exn$Overflow$43); }
  return Math.floor(x / y);
}

SmlPrims.div_w31 = function (x,y,exn) {
  if ( y == 0 ) { throw(exn); }
  return Math.floor(x / y);
}

SmlPrims.div_w32 = function (x,y,exn) {
  if ( y == 0 ) { throw(exn); }
  return Math.floor(x / y);
}

SmlPrims.mod_w31 = function (x,y,exn) {
  if ( y == 0 ) { throw(exn); }
  return x % y;
}

SmlPrims.mod_w32 = function (x,y,exn) {
  if ( y == 0 ) { throw(exn); }
  return x % y;
}

SmlPrims.quot = function (x,y) {
  if ((x < 0 && y >= 0) || (x >= 0 && y < 0)) {
     return Math.ceil(x / y);
  } else {
     return Math.floor(x / y);
  }
}

SmlPrims.w32_to_i32_X = function(x) {
  if ( x > 0x7FFFFFFF ) {
    return -(0xFFFFFFFF - x) - 1;
  } else {
    return x;
  }
}

SmlPrims.w31_to_i32_X = function(x) {
  if ( x > 0x3FFFFFFF ) {
    return -(0x7FFFFFFF - x) - 1;
  } else {
    return x;
  }
}

SmlPrims.w31_to_w32_X = function(x) {
  if ( x > 0x3FFFFFFF ) {
    return (x & 0x3FFFFFFF) | (1 << 31);
  } else {
    return x;
  }
}

SmlPrims.i32_to_w32 = function(x) {
  if ( x < 0 ) {
    return 0xFFFFFFFF - (-x) + 1;
  } else {
    return x;
  }
}

SmlPrims.i32_to_w31 = function(x) {
  if ( x < 0 ) {
    return SmlPrims.cut_w31(0xFFFFFFFF - (-x) + 1);
  } else {
    return SmlPrims.cut_w31(x);
  }
}

SmlPrims.sinh = function(x) {
  var tmp = Math.exp(x);
  return (tmp - 1 / tmp) / 2;
}

SmlPrims.cosh = function(x) {
  var tmp = Math.exp(x);
  return (tmp + 1 / tmp) / 2;
}

SmlPrims.tanh = function(x) {
  var tmp = Math.exp(x);
  return (tmp - 1 / tmp) / (tmp + 1 / tmp);
}

SmlPrims.trunc = function(x) {
  if ( x >= 0 ) { return Math.floor(x); }
  return Math.ceil(x);
}