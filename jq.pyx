import json

from cpython.bytes cimport PyBytes_AsString
    

cdef extern from "jv.h":
    ctypedef enum jv_kind:
      JV_KIND_INVALID,
      JV_KIND_NULL,
      JV_KIND_FALSE,
      JV_KIND_TRUE,
      JV_KIND_NUMBER,
      JV_KIND_STRING,
      JV_KIND_ARRAY,
      JV_KIND_OBJECT

    ctypedef struct jv:
        pass
    
    jv_kind jv_get_kind(jv)
    int jv_is_valid(jv)
    jv jv_copy(jv)
    void jv_free(jv)
    jv jv_invalid_get_msg(jv)
    int jv_invalid_has_msg(jv)
    char* jv_string_value(jv)
    jv jv_dump_string(jv, int flags)
    
    cdef struct jv_parser:
        pass
    
    jv_parser* jv_parser_new(int)
    void jv_parser_free(jv_parser*)
    void jv_parser_set_buf(jv_parser*, const char*, int, int)
    jv jv_parser_next(jv_parser*)


cdef extern from "jq.h":
    ctypedef struct jq_state:
        pass
    
    ctypedef void (*jq_err_cb)(void *, jv)
        
    jq_state *jq_init()
    void jq_teardown(jq_state **)
    int jq_compile(jq_state *, const char* str)
    void jq_start(jq_state *, jv value, int flags)
    jv jq_next(jq_state *)
    void jq_set_error_cb(jq_state *, jq_err_cb, void *)
    void jq_get_error_cb(jq_state *, jq_err_cb *, void **)
    

def jq(object program):
    cdef object program_bytes_obj = program.encode("utf8")
    cdef char* program_bytes = program_bytes_obj
    cdef jq_state *jq = jq_init()
    if not jq:
        raise Exception("jq_init failed")
    
    cdef _ErrorStore error_store = _ErrorStore.__new__(_ErrorStore)
    error_store.clear()
    
    jq_set_error_cb(jq, store_error, <void*>error_store)
    
    cdef int compiled = jq_compile(jq, program_bytes)
    
    if error_store.has_errors():
        raise ValueError(error_store.error_string())

    # TODO: unset error callback?
    
    if not compiled:
        raise ValueError("program was not valid")
    
    cdef _Program wrapped_program = _Program.__new__(_Program)
    wrapped_program._jq = jq
    wrapped_program._error_store = error_store
    return wrapped_program


cdef void store_error(void* store_ptr, jv error):
    # TODO: handle errors not of JV_KIND_STRING
    cdef _ErrorStore store = <_ErrorStore>store_ptr
    if jv_get_kind(error) == JV_KIND_STRING:
        store.store_error(jv_string_value(error))


cdef class _ErrorStore(object):
    cdef object _errors
    
    cdef int has_errors(self):
        return len(self._errors)
    
    cdef object error_string(self):
        return "\n".join(self._errors)
    
    cdef void store_error(self, char* error):
        self._errors.append(error.decode("utf8"))
    
    cdef void clear(self):
        self._errors = []


class EmptyValue(object):
    pass

_NO_VALUE = EmptyValue()

cdef class _Program(object):
    cdef jq_state* _jq
    cdef _ErrorStore _error_store

#~     def __dealloc__(self):
#~         jq_teardown(&self._jq)
    
    def execute(self, value=_NO_VALUE, text=_NO_VALUE):
        if (value is _NO_VALUE) == (text is _NO_VALUE):
            raise ValueError("Either the value or text argument should be set")
        string_input = text if text is not _NO_VALUE else json.dumps(value)
        
        self._error_store.clear()
        
        # TODO: handle interleaved calls
        
        cdef _Result result = _Result.__new__(_Result)
        result._execute(self._jq, string_input)
        return result


cdef class _Result(object):
    cdef jq_state* _jq
    cdef jv_parser* _parser
    cdef object _bytes_input
    cdef bint _ready
    cdef bint _done
    
    cdef void _execute(self, jq_state* jq, object string_input):
        self._jq = jq
        self._done = False
        self._ready = False
        cdef jv_parser* parser = jv_parser_new(0)
        self._bytes_input = string_input.encode("utf8")
        cdef char* cbytes_input = PyBytes_AsString(self._bytes_input)
        jv_parser_set_buf(parser, cbytes_input, len(cbytes_input), 0)
        self._parser = parser
        print("AAA")
    
    def __iter__(self):
        return self
    
    def __next__(self):
        cdef int dumpopts = 0
        while True:
            if not self._ready:
                self._ready_next_input()
                self._ready = True
        
            result = jq_next(self._jq)
            if jv_is_valid(result):
                dumped = jv_dump_string(result, dumpopts)
                # TODO: __next__ should return json values, not text
                return jv_string_value(dumped)
                # TODO: unnecessary?
                #jv_free(dumped)
            elif jv_invalid_has_msg(jv_copy(result)):
                error_message = jv_invalid_get_msg(result)
                message = jv_string_value(error_message)
                raise ValueError(message)
            else:
                self._ready = False
        
    cdef _ready_next_input(self):
        cdef int jq_flags = 0
        cdef jv value = jv_parser_next(self._parser)
        if jv_is_valid(value):
            jq_start(self._jq, value, jq_flags)
        elif jv_invalid_has_msg(jv_copy(value)):
            error_message = jv_invalid_get_msg(value)
            message = jv_string_value(error_message)
            raise ValueError(b"parse error: " + message)
        else:
            raise StopIteration()
            
    def text(self):
        return "\n".join(self)
    
    def all(self):
        return [
            json.loads(result_bytes.decode("utf-8"))
            for result_bytes in self
        ]
    
    def first(self):
        return self.all()[0]

    
def execute(program, value=_NO_VALUE, text=_NO_VALUE):
    return jq(program).execute(value, text=text)
