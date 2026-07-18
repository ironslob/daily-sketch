"""Unit tests for prompt word validation and deterministic generation."""

from __future__ import annotations

from datetime import date

import pytest

from app.seeds.prompts import (
    generate_prompt_words,
    load_word_list,
    validate_prompt_words,
)


def test_load_word_list_contains_enough_words() -> None:
    words = load_word_list()
    assert len(words) >= 3
    assert all(word.strip() for word in words)


def test_validate_prompt_words_accepts_three_distinct() -> None:
    assert validate_prompt_words(("Chocolate", "Coffee", "Banana")) == (
        "Chocolate",
        "Coffee",
        "Banana",
    )


def test_validate_prompt_words_rejects_empty() -> None:
    with pytest.raises(ValueError, match="non-empty"):
        validate_prompt_words(("Chocolate", " ", "Banana"))


def test_validate_prompt_words_rejects_duplicates() -> None:
    with pytest.raises(ValueError, match="unique"):
        validate_prompt_words(("Coffee", "coffee", "Banana"))


def test_generate_prompt_words_is_deterministic_and_ordered() -> None:
    catalog = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot"]
    first = generate_prompt_words(date(2026, 7, 18), catalog)
    second = generate_prompt_words(date(2026, 7, 18), catalog)
    other = generate_prompt_words(date(2026, 7, 19), catalog)

    assert first == second
    assert len(set(first)) == 3
    assert all(word in catalog for word in first)
    assert other  # different date still produces a valid triple
    assert len(set(other)) == 3
