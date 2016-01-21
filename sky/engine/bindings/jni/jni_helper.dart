// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of dart_jni;

class JavaError extends Error {
  JavaError(this._message);
  String _message;
  String toString() => _message;
}

// JNI methods used to invoke Java reflection
class _JavaReflect {
  JniClass classClazz;
  int classForName;
  int classGetConstructors;
  int classGetFields;
  int classGetMethods;
  int classGetName;
  int constructorGetParameterTypes;
  int fieldGetType;
  int memberGetModifiers;
  int memberGetName;
  int methodGetParameterTypes;
  int methodGetReturnType;
  int objectGetClass;
  int objectToString;

  int modifierStatic;

  _JavaReflect() {
    classClazz = JniClass.fromName('java.lang.Class');
    classForName = classClazz.getStaticMethodId('forName',
        '(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;');
    classGetConstructors = classClazz.getMethodId('getConstructors',
        '()[Ljava/lang/reflect/Constructor;');
    classGetFields = classClazz.getMethodId('getFields', '()[Ljava/lang/reflect/Field;');
    classGetMethods = classClazz.getMethodId('getMethods', '()[Ljava/lang/reflect/Method;');
    classGetName = classClazz.getMethodId('getName', '()Ljava/lang/String;');

    JniClass constructorClazz = JniClass.fromName('java.lang.reflect.Constructor');
    constructorGetParameterTypes = constructorClazz.getMethodId(
        'getParameterTypes', '()[Ljava/lang/Class;');

    JniClass fieldClazz = JniClass.fromName('java.lang.reflect.Field');
    fieldGetType = fieldClazz.getMethodId('getType', '()Ljava/lang/Class;');

    JniClass memberClazz = JniClass.fromName('java.lang.reflect.Member');
    memberGetModifiers = memberClazz.getMethodId('getModifiers', '()I');
    memberGetName = memberClazz.getMethodId('getName', '()Ljava/lang/String;');

    JniClass methodClazz = JniClass.fromName('java.lang.reflect.Method');
    methodGetParameterTypes = methodClazz.getMethodId(
        'getParameterTypes', '()[Ljava/lang/Class;');
    methodGetReturnType = methodClazz.getMethodId(
        'getReturnType', '()Ljava/lang/Class;');

    JniClass modifierClazz = JniClass.fromName('java.lang.reflect.Modifier');
    modifierStatic = modifierClazz.getStaticIntField(
        modifierClazz.getStaticFieldId('STATIC', 'I'));

    JniClass objectClazz = JniClass.fromName('java.lang.Object');
    objectGetClass = objectClazz.getMethodId('getClass', '()Ljava/lang/Class;');
    objectToString = objectClazz.getMethodId('toString', '()Ljava/lang/String;');
  }
}

final _JavaReflect _reflect = new _JavaReflect();

class _JavaType {
  final String name;

  _JavaType(this.name);

  String toString() => 'JavaType:$name';
}

class _JavaPrimitive {
  static final _JavaType jvoid = new _JavaType('void');
  static final _JavaType jboolean = new _JavaType('boolean');
  static final _JavaType jbyte = new _JavaType('byte');
  static final _JavaType jchar = new _JavaType('char');
  static final _JavaType jshort = new _JavaType('short');
  static final _JavaType jint = new _JavaType('int');
  static final _JavaType jlong = new _JavaType('long');
  static final _JavaType jfloat = new _JavaType('float');
  static final _JavaType jdouble = new _JavaType('double');
}

Map<String, _JavaType> _primitiveMap = <String, _JavaType>{
  'void': _JavaPrimitive.jvoid,
  'boolean': _JavaPrimitive.jboolean,
  'byte': _JavaPrimitive.jbyte,
  'char': _JavaPrimitive.jchar,
  'short': _JavaPrimitive.jshort,
  'int': _JavaPrimitive.jint,
  'long': _JavaPrimitive.jlong,
  'float': _JavaPrimitive.jfloat,
  'double': _JavaPrimitive.jdouble,
};

_JavaType _javaTypeForClass(JniObject clazz) {
  String className = JniString.unwrap(clazz.callObjectMethod(_reflect.classGetName, []));

  _JavaType primitive = _primitiveMap[className];
  if (primitive != null)
    return primitive;

  return new _JavaType(className);
}

class _JavaField {
  String name;
  int fieldId;
  _JavaType type;
  int modifiers;

  _JavaField(JniObject field) {
    name = JniString.unwrap(field.callObjectMethod(_reflect.memberGetName, []));
    fieldId = JniApi.fromReflectedField(field);
    type = _javaTypeForClass(
        field.callObjectMethod(_reflect.fieldGetType, []));
    modifiers = field.callIntMethod(_reflect.memberGetModifiers, []);
  }

  bool get isStatic => (modifiers & _reflect.modifierStatic) != 0;
}

abstract class _HasArguments {
  String get name;
  List<_JavaType> get argTypes;
}

class _JavaMethod implements _HasArguments {
  String _name;
  int methodId;
  _JavaType returnType;
  int modifiers;
  List<_JavaType> _argTypes;

  _JavaMethod(JniObject method) {
    _name = JniString.unwrap(method.callObjectMethod(_reflect.memberGetName, []));
    methodId = JniApi.fromReflectedMethod(method);
    returnType = _javaTypeForClass(
        method.callObjectMethod(_reflect.methodGetReturnType, []));
    modifiers = method.callIntMethod(_reflect.memberGetModifiers, []);

    JniObjectArray argClasses = method.callObjectMethod(_reflect.methodGetParameterTypes, []);
    _argTypes = new List<_JavaType>();
    for (JniObject argClass in argClasses) {
      _argTypes.add(_javaTypeForClass(argClass));
    }
  }

  String get name => _name;
  List<_JavaType> get argTypes => _argTypes;

  bool get isStatic => (modifiers & _reflect.modifierStatic) != 0;
}

class _JavaConstructor implements _HasArguments {
  String _name;
  int methodId;
  List<_JavaType> _argTypes;

  _JavaConstructor(JniObject ctor) {
    _name = JniString.unwrap(ctor.callObjectMethod(_reflect.memberGetName, []));
    methodId = JniApi.fromReflectedMethod(ctor);

    JniObjectArray argClasses = ctor.callObjectMethod(
        _reflect.constructorGetParameterTypes, []);
    _argTypes = new List<_JavaType>();
    for (JniObject argClass in argClasses) {
      _argTypes.add(_javaTypeForClass(argClass));
    }
  }

  String get name => _name;
  List<_JavaType> get argTypes => _argTypes;
}

// Given a list of overloaded methods, select one that is the best match for
// the provided arguments.
_HasArguments _findMatchingMethod(List<_HasArguments> overloads, List args) {
  if (overloads.length == 1) {
    if (overloads[0].argTypes.length == args.length)
      return overloads[0];
    throw new JavaError('Argument mismatch when invoking method ${overloads[0].name}');
  }

  for (_HasArguments overload in overloads) {
    if (overload.argTypes.length == args.length) {
      return overload;
    }
  }

  throw new JavaError('Unable to find matching method for ${overloads[0].name}');
}

// Convert an object received from JNI into the corresponding Dart type.
dynamic _javaObjectToDart(JniObject object) {
  if (object == null)
    return null;

  if (object is JniString)
    return object.text;

  if (object is JniClass)
    return Java.wrapClassObject(object);

  return new JavaObject(object);
}

// Convert a Dart object to a type suitable for passing to JNI.
dynamic _dartObjectToJava(dynamic object) {
  if (object == null)
    return object;

  if (object is JniObject)
    return object;

  if (object is JavaObject)
    return object.jniObject;

  if (object is num || object is bool || object is JniFloat)
    return object;

  if (object is String)
    return JniString.create(object);

  throw new JavaError('Unable to convert Dart object to Java: $object');
}

class Java {
  static final Map<String, JavaClass> _classCache = new Map<String, JavaClass>();

  // Returns a JavaClass for the given class name
  static JavaClass getClass(String className) {
    JavaClass cacheEntry = _classCache[className];
    if (cacheEntry != null)
      return cacheEntry;

    // Load and initialize the class
    JniClass jniClass = _reflect.classClazz.callStaticObjectMethod(
        _reflect.classForName,
        [className, true, JniApi.getClassLoader()]
    );

    JavaClass javaClass = new JavaClass._(jniClass);
    _classCache[javaClass.className] = javaClass;
    return javaClass;
  }

  // Returns a JavaClass that wraps a raw JNI class object
  static JavaClass wrapClassObject(dynamic classObject) {
    JniClass jniClass;
    if (classObject is JniClass) {
      jniClass = classObject;
    } else if (classObject is JavaObject && classObject.jniObject is JniClass) {
      jniClass = classObject.jniObject;
    } else {
      throw new JavaError('fromClassObject: $classObject is not a Java class');
    }

    String className = JniString.unwrap(jniClass.callObjectMethod(_reflect.classGetName, []));
    JavaClass cacheEntry = _classCache[className];
    if (cacheEntry != null)
      return cacheEntry;

    JavaClass javaClass = new JavaClass._(jniClass);
    _classCache[javaClass.className] = javaClass;
    return javaClass;
  }
}

// A wrapper for a JNI class that uses reflection to provide access to the
// class' static fields, methods, and constructors.
class JavaClass {
  JniClass _clazz;
  String _className;
  Map<Symbol, _JavaField> _fields;
  Map<Symbol, _JavaField> _staticFields;
  Map<Symbol, List<_JavaMethod>> _methods;
  Map<Symbol, List<_JavaMethod>> _staticMethods;
  List<_JavaConstructor> _constructors;

  static final Symbol _newInstanceSymbol = new Symbol('newInstance');

  JavaClass._(JniClass classObject) {
    _clazz = classObject;
    _className = JniString.unwrap(_clazz.callObjectMethod(_reflect.classGetName, []));

    _fields = new Map<Symbol, _JavaField>();
    _staticFields = new Map<Symbol, _JavaField>();
    JniObjectArray reflectFields = _clazz.callObjectMethod(_reflect.classGetFields, []);
    for (JniObject reflectField in reflectFields) {
      _JavaField javaField = new _JavaField(reflectField);
      Map<Symbol, _JavaField> fieldMap =
          javaField.isStatic ? _staticFields : _fields;
      fieldMap[new Symbol(javaField.name)] = javaField;

      // Dart will identify the field setter with a symbol name ending with an equal sign.
      fieldMap[new Symbol(javaField.name + '=')] = javaField;
    }

    _methods = new Map<Symbol, List<_JavaMethod>>();
    _staticMethods = new Map<Symbol, List<_JavaMethod>>();
    JniObjectArray reflectMethods = _clazz.callObjectMethod(_reflect.classGetMethods, []);
    for (JniObject reflectMethod in reflectMethods) {
      _JavaMethod javaMethod = new _JavaMethod(reflectMethod);
      Map<Symbol, List<_JavaMethod>> methodMap =
          javaMethod.isStatic ? _staticMethods : _methods;
      Symbol symbol = new Symbol(javaMethod.name);
      List<_JavaMethod> overloads = methodMap[symbol];
      if (overloads != null) {
        overloads.add(javaMethod);
      } else {
        methodMap[symbol] = <_JavaMethod>[javaMethod];
      }
    }

    _constructors = new List<_JavaConstructor>();
    JniObjectArray reflectCtors = _clazz.callObjectMethod(_reflect.classGetConstructors, []);
    for (JniObject ctor in reflectCtors) {
      _constructors.add(new _JavaConstructor(ctor));
    }
  }

  String toString() => 'JavaClass:$_className';

  String get className => _className;

  JniClass get jniClass => _clazz;

  // Return a JavaObject representing the java.lang.Class instance for this class
  JavaObject get asJavaObject => new JavaObject(_clazz);

  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      List args = invocation.positionalArguments.map(_dartObjectToJava).toList();

      if (invocation.memberName == _newInstanceSymbol) {
        _JavaConstructor ctor = _findMatchingMethod(_constructors, args);
        return new JavaObject(_clazz.newObject(ctor.methodId, args));
      }

      List<_JavaMethod> overloads = _staticMethods[invocation.memberName];
      if (overloads == null)
        throw new JavaError('Static method ${invocation.memberName} not found');

      _JavaMethod method = _findMatchingMethod(overloads, args);

      if (method.returnType == _JavaPrimitive.jvoid) {
        return _clazz.callStaticVoidMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jboolean) {
        return _clazz.callStaticBooleanMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jbyte) {
        return _clazz.callStaticByteMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jchar) {
        return _clazz.callStaticCharMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jshort) {
        return _clazz.callStaticShortMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jint) {
        return _clazz.callStaticIntMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jlong) {
        return _clazz.callStaticLongMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jfloat) {
        return _clazz.callStaticFloatMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jdouble) {
        return _clazz.callStaticDoubleMethod(method.methodId, args);
      } else {
        return _javaObjectToDart(
            _clazz.callStaticObjectMethod(method.methodId, args));
      }
    }

    if (invocation.isGetter) {
      _JavaField field = _staticFields[invocation.memberName];
      if (field == null)
        throw new JavaError('Static field ${invocation.memberName} not found');

      if (field.type == _JavaPrimitive.jboolean) {
        return _clazz.getStaticBooleanField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jbyte) {
        return _clazz.getStaticByteField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jchar) {
        return _clazz.getStaticCharField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jshort) {
        return _clazz.getStaticShortField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jint) {
        return _clazz.getStaticIntField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jlong) {
        return _clazz.getStaticLongField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jfloat) {
        return _clazz.getStaticFloatField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jdouble) {
        return _clazz.getStaticDoubleField(field.fieldId);
      } else {
        return _javaObjectToDart(_clazz.getStaticObjectField(field.fieldId));
      }
    }

    if (invocation.isSetter) {
      _JavaField field = _staticFields[invocation.memberName];
      if (field == null)
        throw new JavaError('Static field ${invocation.memberName} not found');

      dynamic value = invocation.positionalArguments[0];

      if (field.type == _JavaPrimitive.jboolean) {
        _clazz.setStaticBooleanField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jbyte) {
        _clazz.setStaticByteField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jchar) {
        _clazz.setStaticCharField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jshort) {
        _clazz.setStaticShortField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jint) {
        _clazz.setStaticIntField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jlong) {
        _clazz.setStaticLongField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jfloat) {
        _clazz.setStaticFloatField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jdouble) {
        _clazz.setStaticDoubleField(field.fieldId, value);
      } else {
        _clazz.setStaticObjectField(field.fieldId, _dartObjectToJava(value));
      }

      return null;
    }

    throw new JavaError('Unable to access ${invocation.memberName}');
  }
}

// A wrapper for a JNI object that provides access to the object's fields
// and methods.
class JavaObject {
  JniObject _object;
  JavaClass _clazz;

  JavaObject(JniObject object) {
    _object = object;

    _clazz = Java.wrapClassObject(
        _object.callObjectMethod(_reflect.objectGetClass, []));
  }

  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      List args = invocation.positionalArguments.map(_dartObjectToJava).toList();

      List<_JavaMethod> overloads = _clazz._methods[invocation.memberName];
      if (overloads == null)
        throw new JavaError('Method ${invocation.memberName} not found');

      _JavaMethod method = _findMatchingMethod(overloads, args);

      if (method.returnType == _JavaPrimitive.jvoid) {
        return _object.callVoidMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jboolean) {
        return _object.callBooleanMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jbyte) {
        return _object.callByteMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jchar) {
        return _object.callCharMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jshort) {
        return _object.callShortMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jint) {
        return _object.callIntMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jlong) {
        return _object.callLongMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jfloat) {
        return _object.callFloatMethod(method.methodId, args);
      } else if (method.returnType == _JavaPrimitive.jdouble) {
        return _object.callDoubleMethod(method.methodId, args);
      } else {
        return _javaObjectToDart(
            _object.callObjectMethod(method.methodId, args));
      }
    }

    if (invocation.isGetter) {
      _JavaField field = _clazz._fields[invocation.memberName];
      if (field == null)
        throw new JavaError('Field ${invocation.memberName} not found');

      if (field.type == _JavaPrimitive.jboolean) {
        return _object.getBooleanField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jbyte) {
        return _object.getByteField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jchar) {
        return _object.getCharField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jshort) {
        return _object.getShortField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jint) {
        return _object.getIntField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jlong) {
        return _object.getLongField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jfloat) {
        return _object.getFloatField(field.fieldId);
      } else if (field.type == _JavaPrimitive.jdouble) {
        return _object.getDoubleField(field.fieldId);
      } else {
        return _javaObjectToDart(_object.getObjectField(field.fieldId));
      }
    }

    if (invocation.isSetter) {
      _JavaField field = _clazz._fields[invocation.memberName];
      if (field == null)
        throw new JavaError('Field ${invocation.memberName} not found');

      dynamic value = invocation.positionalArguments[0];

      if (field.type == _JavaPrimitive.jboolean) {
        _object.setBooleanField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jbyte) {
        _object.setByteField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jchar) {
        _object.setCharField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jshort) {
        _object.setShortField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jint) {
        _object.setIntField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jlong) {
        _object.setLongField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jfloat) {
        _object.setFloatField(field.fieldId, value);
      } else if (field.type == _JavaPrimitive.jdouble) {
        _object.setDoubleField(field.fieldId, value);
      } else {
        _object.setObjectField(field.fieldId, _dartObjectToJava(value));
      }

      return null;
    }

    throw new JavaError('Unable to access ${invocation.memberName}');
  }

  String toString() {
    return JniString.unwrap(_object.callObjectMethod(_reflect.objectToString, []));
  }

  JavaClass get javaClass => _clazz;

  JniObject get jniObject => _object;
}
