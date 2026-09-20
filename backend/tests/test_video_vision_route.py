import base64

from app.api.routes.vision import VideoAnalyzeRequest, analyze_video


class _Service:
    def analyze_video(self, **kwargs):
        assert kwargs["mime_type"] == "video/mp4"
        return {"visual_summary": "a leaking pipe", "spoken_transcript": "please find a plumber"}


class _Container:
    universal_image_service = _Service()


class _State:
    container = _Container()


class _App:
    state = _State()


class _Request:
    app = _App()


def test_video_route_returns_combined_visual_and_spoken_evidence():
    result = analyze_video(
        VideoAnalyzeRequest(
            video_base64=base64.b64encode(b"video").decode("ascii"),
            mime_type="video/mp4",
            user_text="find help",
            language="en",
        ),
        _Request(),
    )

    assert result["analysis"]["visual_summary"] == "a leaking pipe"
    assert result["analysis"]["spoken_transcript"] == "please find a plumber"