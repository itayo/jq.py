# coding=utf8

from __future__ import unicode_literals

from nose.tools import istest, assert_equal, assert_raises

from jq import execute, jq


@istest
def output_of_dot_operator_is_input():
    assert_equal(
        "42",
        jq(".").execute("42").first()
    )


@istest
def can_add_one_to_each_element_of_an_array():
    assert_equal(
        [2, 3, 4],
        jq("[.[]+1]").execute([1, 2, 3]).first()
    )


@istest
def can_use_regexes():
    assert_equal(
        True,
        jq('test(".*")').execute("42").first()
    )


@istest
def input_string_is_parsed_to_json_if_raw_input_is_true():
    assert_equal(
        42,
        jq(".").execute(text="42").first()
    )


@istest
def output_is_serialised_to_json_string_if_text_output_is_true():
    assert_equal(
        '"42"',
        jq(".").execute("42").text()
    )


@istest
def elements_in_text_output_are_separated_by_newlines():
    assert_equal(
        "1\n2\n3",
        jq(".[]").execute([1, 2, 3]).text()
    )


@istest
def first_output_element_is_returned_if_multiple_output_is_false_but_there_are_multiple_output_elements():
    assert_equal(
        2,
        jq(".[]+1").execute([1, 2, 3]).first()
    )


@istest
def multiple_output_elements_are_returned_if_multiple_output_is_true():
    assert_equal(
        [2, 3, 4],
        jq(".[]+1").execute([1, 2, 3]).all()
    )


@istest
def can_treat_execute_result_as_iterable():
    assert_equal(
        [2, 3, 4],
        list(jq(".[]+1").execute([1, 2, 3]))
    )


@istest
def multiple_inputs_in_raw_input_are_separated_by_newlines():
    assert_equal(
        [2, 3, 4],
        jq(".+1").execute(text="1\n2\n3").all()
    )


@istest
def value_error_is_raised_if_program_is_invalid():
    try:
        jq("!")
        assert False, "Expected error"
    except ValueError as error:
        expected_error_str = "jq: error: syntax error, unexpected INVALID_CHARACTER, expecting $end (Unix shell quoting issues?) at <top-level>, line 1:\n!\njq: 1 compile error"
        assert_equal(str(error), expected_error_str)


@istest
def value_error_is_raised_if_input_cannot_be_processed_by_program():
    program = jq(".x")
    try:
        program.execute(1).all()
        assert False, "Expected error"
    except ValueError as error:
        expected_error_str = "Cannot index number with string \"x\""
        assert_equal(str(error), expected_error_str)


@istest
def errors_do_not_leak_between_transformations():
    program = jq(".x")
    try:
        program.execute(1).all()
        assert False, "Expected error"
    except ValueError as error:
        pass
    
    assert_equal(1, program.execute({"x": 1}).first())


@istest
def value_error_is_raised_if_input_is_not_valid_json():
    program = jq(".x")
    try:
        program.execute(text="!!").first()
        assert False, "Expected error"
    except ValueError as error:
        expected_error_str = "parse error: Invalid numeric literal at EOF at line 1, column 2"
        assert_equal(str(error), expected_error_str)


@istest
def unicode_strings_can_be_used_as_input():
    assert_equal(
        "‽",
        jq(".").execute(text='"‽"').first()
    )


@istest
def unicode_strings_can_be_used_as_programs():
    assert_equal(
        "Dragon‽",
        jq('.+"‽"').execute(text='"Dragon"').first()
    )


@istest
def can_execute_program_without_intermediate_program():
    assert_equal(
        "42",
        execute(".", "42").first()
    )
