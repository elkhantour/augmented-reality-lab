using UnityEditor;
using UnityEngine;
using System.Collections.Generic;

public class BatchShaderSwap : EditorWindow
{
    Shader targetShader;

    // Old property names (tried in order) -> new property name
    static readonly (string[] sources, string target)[] TextureMap =
    {
        (new[] { "_BaseMap", "_MainTex" },        "_BaseMap"),
        // Add more as your shader grows, e.g.:
        // (new[] { "_BumpMap" },                  "_BumpMap"),
        // (new[] { "_MetallicGlossMap" },         "_MetallicGlossMap"),
        // (new[] { "_EmissionMap" },              "_EmissionMap"),
    };

    static readonly (string[] sources, string target)[] ColorMap =
    {
        (new[] { "_BaseColor", "_Color" }, "_BaseColor"),
    };

    [MenuItem("Tools/Batch Shader Swap")]
    static void Open() => GetWindow<BatchShaderSwap>("Batch Shader Swap");

    void OnGUI()
    {
        EditorGUILayout.HelpBox(
            "Select materials or folders in the Project window, pick the target shader, then click Swap.",
            MessageType.Info);

        targetShader = (Shader)EditorGUILayout.ObjectField("Target Shader", targetShader, typeof(Shader), false);

        using (new EditorGUI.DisabledScope(targetShader == null))
        {
            if (GUILayout.Button("Swap Selected Materials"))
                Swap();
        }
    }

    void Swap()
    {
        var materials = new List<Material>();
        foreach (var obj in Selection.GetFiltered(typeof(Material), SelectionMode.DeepAssets))
            materials.Add((Material)obj);

        int count = 0;
        foreach (var mat in materials)
        {
            if (mat.shader == targetShader) continue;
            Undo.RecordObject(mat, "Batch Shader Swap");

            // 1. Read everything from the OLD shader first
            var textures = new List<(string target, Texture tex, Vector2 scale, Vector2 offset)>();
            foreach (var (sources, target) in TextureMap)
                foreach (var src in sources)
                    if (mat.HasProperty(src))
                    {
                        textures.Add((target, mat.GetTexture(src), mat.GetTextureScale(src), mat.GetTextureOffset(src)));
                        break;
                    }

            var colors = new List<(string target, Color color)>();
            foreach (var (sources, target) in ColorMap)
                foreach (var src in sources)
                    if (mat.HasProperty(src))
                    {
                        colors.Add((target, mat.GetColor(src)));
                        break;
                    }

            // 2. Swap the shader
            mat.shader = targetShader;

            // 3. Write values back to the NEW shader
            foreach (var t in textures)
                if (mat.HasProperty(t.target))
                {
                    mat.SetTexture(t.target, t.tex);
                    mat.SetTextureScale(t.target, t.scale);
                    mat.SetTextureOffset(t.target, t.offset);
                }

            foreach (var c in colors)
                if (mat.HasProperty(c.target))
                    mat.SetColor(c.target, c.color);

            EditorUtility.SetDirty(mat);
            count++;
        }

        AssetDatabase.SaveAssets();
        Debug.Log($"Batch Shader Swap: converted {count} material(s) to {targetShader.name}.");
    }
}
