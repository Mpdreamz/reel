import java.util.HashMap;
import java.util.Map;

/** When narration plays during a recording. Lines never overlap. */
public final class SpeechClock {
    private double speechEnd = 0;
    private final Map<String, Double> markers = new HashMap<>();

    /** Starts a line now, or after the line before it. */
    public double[] say(Line line, double now, boolean over) {
        double start = Math.max(now, speechEnd);
        speechEnd = start + line.duration();
        line.markerOffsets().forEach(
            (name, offset) -> markers.put(name, start + offset));
        return new double[] { start, over ? start : speechEnd };
    }

    /** When the narration reaches a marker, or null before it starts. */
    public Double time(String marker) {
        return markers.get(marker);
    }
}
