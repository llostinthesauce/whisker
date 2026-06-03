import re


_SPACES_RE = re.compile(r"[ \t\r\f\v]+")
_MULTI_NEWLINES_RE = re.compile(r"\n{3,}")
_SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")


def normalize_whitespace(text: str) -> str:
    collapsed = _SPACES_RE.sub(" ", text.replace("\u00a0", " "))
    collapsed = _MULTI_NEWLINES_RE.sub("\n\n", collapsed)
    return collapsed.strip()


def clean_text(text: str, mode: str) -> str:
    selected = (mode or "raw").strip().lower()
    if selected == "raw":
        return text

    cleaned = normalize_whitespace(text)
    if selected == "light":
        return cleaned

    if selected == "message":
        return _sentence_start(cleaned)

    if selected == "email":
        return _sentence_start(cleaned)

    if selected == "notes":
        return "\n".join(_split_sentences(cleaned))

    if selected == "bullets":
        return "\n".join(f"- {sentence}" for sentence in _split_sentences(cleaned))

    return cleaned


def _sentence_start(text: str) -> str:
    if not text:
        return text
    return text[0].upper() + text[1:]


def _split_sentences(text: str) -> list[str]:
    sentences = [
        _sentence_start(part.strip())
        for part in _SENTENCE_SPLIT_RE.split(text)
        if part.strip()
    ]
    return sentences or ([text] if text else [])
