using System.Collections;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

/// One dialog shared by every map pointer. Put this on the ROOT of your dialog Canvas
/// (not on the panel, which gets hidden) and drag your UI objects into the slots.
public class MapPointDialog : MonoBehaviour
{
    public static MapPointDialog Instance { get; private set; }

    [Header("UI references")]
    [Tooltip("The object that gets shown/hidden (a child of this canvas).")]
    public GameObject panel;
    public Image image;
    public TMP_Text headline;
    public TMP_Text body;
    public Button closeButton;
    [Tooltip("Optional: a full-screen button behind the card; tapping it closes the dialog.")]
    public Button backdropButton;

    [Header("Fade (optional)")]
    public CanvasGroup canvasGroup;
    public float fadeTime = 0.15f;

    public bool IsOpen => panel != null && panel.activeSelf;

    Coroutine fade;

    void Awake()
    {
        Instance = this;

        if (closeButton != null) closeButton.onClick.AddListener(Hide);
        if (backdropButton != null) backdropButton.onClick.AddListener(Hide);

        if (panel != null) panel.SetActive(false);
    }

    void OnDestroy()
    {
        if (Instance == this) Instance = null;
    }

    public void Show(MapPointData data)
    {
        if (data == null || panel == null) return;

        if (headline != null) headline.text = data.headline;
        if (body != null) body.text = data.body;

        if (image != null)
        {
            image.sprite = data.image;
            image.preserveAspect = true;
            image.gameObject.SetActive(data.image != null); // hide the slot if there's no picture
        }

        panel.SetActive(true);
        StartFade(0f, 1f, false);
    }

    public void Hide()
    {
        if (!IsOpen) return;
        StartFade(canvasGroup != null ? canvasGroup.alpha : 1f, 0f, true);
    }

    void StartFade(float from, float to, bool disableAtEnd)
    {
        if (fade != null) StopCoroutine(fade);

        if (canvasGroup == null || fadeTime <= 0f)
        {
            if (canvasGroup != null) canvasGroup.alpha = to;
            if (disableAtEnd) panel.SetActive(false);
            return;
        }

        fade = StartCoroutine(Fade(from, to, disableAtEnd));
    }

    IEnumerator Fade(float from, float to, bool disableAtEnd)
    {
        float t = 0f;
        canvasGroup.alpha = from;

        while (t < fadeTime)
        {
            t += Time.unscaledDeltaTime;
            canvasGroup.alpha = Mathf.Lerp(from, to, t / fadeTime);
            yield return null;
        }

        canvasGroup.alpha = to;
        if (disableAtEnd) panel.SetActive(false);
        fade = null;
    }
}
