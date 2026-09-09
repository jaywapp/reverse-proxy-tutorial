internal static class Check
{
    public static int Count { get; private set; }
    public static void That(bool condition, string name)
    {
        if (!condition) throw new Exception(name);
        Count++;
    }
    public static async Task ThrowsAsync<T>(Func<Task> action, string name) where T : Exception
    {
        try { await action(); } catch (T) { Count++; return; }
        throw new Exception(name);
    }
}
