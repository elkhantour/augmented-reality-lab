using UnityEngine;
using UnityEngine.EventSystems;

/// Moves `cityRoot` from your own UI. Drag your four arrow objects into the slots below.
/// Hold detection is added to them automatically at startup, so no extra components are needed.
public class CityMover : MonoBehaviour
{
    [Header("Target")]
    public Transform cityRoot;           // can also be assigned from code with SetCity()
    public Camera referenceCamera;       // leave empty to use Camera.main
    public bool relativeToCamera = true; // up = away from camera; off = world axes

    [Header("Arrow buttons (any UI object with a raycast-enabled Graphic)")]
    public GameObject upButton;
    public GameObject downButton;
    public GameObject leftButton;
    public GameObject rightButton;

    [Header("Movement")]
    public float speed = 0.3f;           // world units per second while held
    public float stepDistance = 0.1f;    // distance for single-tap steps (Step* methods)
    public bool smooth = true;
    [Min(0.01f)] public float smoothTime = 0.08f;

    Vector2 held;        // continuous input, each axis -1..1
    Vector3 velocity;    // for SmoothDamp
    Vector3 target;
    bool hasTarget;

    // ---------- Public API (still available for joysticks, code, EventTrigger...) ----------
    public void SetUp(bool pressed)    => held.y = pressed ? 1f : (held.y > 0 ? 0f : held.y);
    public void SetDown(bool pressed)  => held.y = pressed ? -1f : (held.y < 0 ? 0f : held.y);
    public void SetLeft(bool pressed)  => held.x = pressed ? -1f : (held.x < 0 ? 0f : held.x);
    public void SetRight(bool pressed) => held.x = pressed ? 1f : (held.x > 0 ? 0f : held.x);

    public void SetInput(Vector2 input) => held = Vector2.ClampMagnitude(input, 1f);

    public void StepUp()    => Step(Vector2.up);
    public void StepDown()  => Step(Vector2.down);
    public void StepLeft()  => Step(Vector2.left);
    public void StepRight() => Step(Vector2.right);

    public void Step(Vector2 dir)
    {
        if (cityRoot == null) return;
        if (!hasTarget) { target = cityRoot.position; hasTarget = true; }
        target += ToWorld(dir) * stepDistance;
    }

    public void SetCity(Transform t)
    {
        cityRoot = t;
        hasTarget = false;
    }

    // ---------- Internals ----------
    void Awake()
    {
        Hook(upButton, SetUp);
        Hook(downButton, SetDown);
        Hook(leftButton, SetLeft);
        Hook(rightButton, SetRight);
    }

    static void Hook(GameObject go, System.Action<bool> callback)
    {
        if (go == null) return;
        var relay = go.GetComponent<HoldRelay>();
        if (relay == null) relay = go.AddComponent<HoldRelay>();
        relay.onHeld = callback;
    }

    void Update()
    {
        if (cityRoot == null) return;
        if (!hasTarget) { target = cityRoot.position; hasTarget = true; }

        if (held != Vector2.zero)
            target += ToWorld(held) * speed * Time.deltaTime;

        if (smooth)
            cityRoot.position = Vector3.SmoothDamp(cityRoot.position, target, ref velocity, smoothTime);
        else
            cityRoot.position = target;
    }

    Vector3 ToWorld(Vector2 dir)
    {
        Vector3 fwd = Vector3.forward;
        Vector3 right = Vector3.right;

        Camera cam = referenceCamera != null ? referenceCamera : Camera.main;
        if (relativeToCamera && cam != null)
        {
            fwd = Vector3.ProjectOnPlane(cam.transform.forward, Vector3.up);
            if (fwd.sqrMagnitude < 0.001f) // camera looking straight down
                fwd = Vector3.ProjectOnPlane(cam.transform.up, Vector3.up);
            fwd.Normalize();
            right = Vector3.ProjectOnPlane(cam.transform.right, Vector3.up).normalized;
        }
        return right * dir.x + fwd * dir.y;
    }

    // Added automatically to each assigned arrow; reports press and release
    class HoldRelay : MonoBehaviour, IPointerDownHandler, IPointerUpHandler, IPointerExitHandler
    {
        public System.Action<bool> onHeld;
        public void OnPointerDown(PointerEventData e) => onHeld?.Invoke(true);
        public void OnPointerUp(PointerEventData e) => onHeld?.Invoke(false);
        public void OnPointerExit(PointerEventData e) => onHeld?.Invoke(false);
        void OnDisable() => onHeld?.Invoke(false);
    }
}
