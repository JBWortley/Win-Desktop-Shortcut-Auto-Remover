using System;
using System.IO;
using System.Runtime.InteropServices;

internal static class Recycler
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(string path, IntPtr context, ref Guid iid, out IShellItem item);

    internal static string Recycle(string path)
    {
        IShellItem item = null;
        IFileOperation operation = null;
        try
        {
            Guid iid = typeof(IShellItem).GUID;
            SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out item);
            operation = (IFileOperation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("3AD05575-8857-4850-9277-11B85BDB8E09")));
            // SILENT | NOCONFIRMATION | NOERRORUI | NO_CONNECTED_ELEMENTS |
            // RECYCLEONDELETE | EARLYFAILURE | NOCOPYHOOKS. Never request elevation UI.
            operation.SetOperationFlags(0x0004 | 0x0010 | 0x0400 | 0x2000 | 0x00080000 | 0x00100000 | 0x00800000);
            RecycleSink sink = new RecycleSink(path);
            operation.DeleteItem(item, sink);
            operation.PerformOperations();
            bool aborted;
            operation.GetAnyOperationsAborted(out aborted);
            if (aborted || !sink.Completed || sink.Result < 0)
                throw new IOException(sink.Failure ?? "Windows did not complete recycling (HRESULT 0x" + sink.Result.ToString("X8") + ").");
            return sink.RecyclePath;
        }
        finally
        {
            if (operation != null) Marshal.FinalReleaseComObject(operation);
            if (item != null) Marshal.FinalReleaseComObject(item);
        }
    }

    internal static string FileSystemPath(IShellItem item)
    {
        IntPtr text;
        item.GetDisplayName(0x80058000, out text); // SIGDN_FILESYSPATH; never resolve shortcut targets.
        try { return Marshal.PtrToStringUni(text); }
        finally { Marshal.FreeCoTaskMem(text); }
    }
}

[ComVisible(true), ClassInterface(ClassInterfaceType.None)]
public sealed class RecycleSink : IFileOperationProgressSink
{
    private readonly string expected;
    internal bool Completed;
    internal int Result = unchecked((int)0x80004005);
    internal string Failure;
    internal string RecyclePath;
    internal RecycleSink(string path) { expected = Path.GetFullPath(path); }

    public int PreDeleteItem(uint flags, IShellItem item)
    {
        try
        {
            // Veto permanent deletion, including a Shell fallback when recycling isn't available.
            if ((flags & 0x80) == 0) throw new IOException("Windows cannot recycle this item; permanent deletion was blocked.");
            string actual = Recycler.FileSystemPath(item);
            if (!String.Equals(expected, actual, StringComparison.OrdinalIgnoreCase) || !Cleaner.Eligible(actual))
                throw new IOException("Item changed or no longer matches the cleanup rules.");
            return 0;
        }
        catch (Exception ex) { Failure = ex.Message; return unchecked((int)0x80004005); }
    }
    public int PostDeleteItem(uint flags, IShellItem item, int result, IShellItem newlyCreated)
    {
        Result = result;
        Completed = result >= 0;
        if (newlyCreated != null)
        {
            try { RecyclePath = Recycler.FileSystemPath(newlyCreated); }
            catch { /* Some Shell providers don't expose a filesystem path. */ }
        }
        return 0;
    }
    public int StartOperations() { return 0; }
    public int FinishOperations(int result) { return 0; }
    public int PreRenameItem(uint flags, IShellItem item, string name) { return 0; }
    public int PostRenameItem(uint flags, IShellItem item, string name, int result, IShellItem created) { return 0; }
    public int PreMoveItem(uint flags, IShellItem item, IShellItem destination, string name) { return 0; }
    public int PostMoveItem(uint flags, IShellItem item, IShellItem destination, string name, int result, IShellItem created) { return 0; }
    public int PreCopyItem(uint flags, IShellItem item, IShellItem destination, string name) { return 0; }
    public int PostCopyItem(uint flags, IShellItem item, IShellItem destination, string name, int result, IShellItem created) { return 0; }
    public int PreNewItem(uint flags, IShellItem destination, string name) { return 0; }
    public int PostNewItem(uint flags, IShellItem destination, string name, string template, uint attributes, int result, IShellItem created) { return 0; }
    public int UpdateProgress(uint total, uint done) { return 0; }
    public int ResetTimer() { return 0; }
    public int PauseTimer() { return 0; }
    public int ResumeTimer() { return 0; }
}

[ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellItem
{
    void BindToHandler(IntPtr context, ref Guid handler, ref Guid iid, out IntPtr result);
    void GetParent(out IShellItem parent);
    void GetDisplayName(uint kind, out IntPtr name);
    void GetAttributes(uint mask, out uint attributes);
    void Compare(IShellItem other, uint hint, out int order);
}

[ComImport, Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IFileOperation
{
    void Advise(IFileOperationProgressSink sink, out uint cookie);
    void Unadvise(uint cookie);
    void SetOperationFlags(uint flags);
    void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
    void SetProgressDialog(IntPtr dialog);
    void SetProperties(IntPtr properties);
    void SetOwnerWindow(IntPtr owner);
    void ApplyPropertiesToItem(IShellItem item);
    void ApplyPropertiesToItems([MarshalAs(UnmanagedType.IUnknown)] object items);
    void RenameItem(IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, IFileOperationProgressSink sink);
    void RenameItems([MarshalAs(UnmanagedType.IUnknown)] object items, [MarshalAs(UnmanagedType.LPWStr)] string name);
    void MoveItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IFileOperationProgressSink sink);
    void MoveItems([MarshalAs(UnmanagedType.IUnknown)] object items, IShellItem destination);
    void CopyItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IFileOperationProgressSink sink);
    void CopyItems([MarshalAs(UnmanagedType.IUnknown)] object items, IShellItem destination);
    void DeleteItem(IShellItem item, IFileOperationProgressSink sink);
    void DeleteItems([MarshalAs(UnmanagedType.IUnknown)] object items);
    void NewItem(IShellItem destination, uint attributes, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string template, IFileOperationProgressSink sink);
    void PerformOperations();
    void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
}

[ComVisible(true), Guid("04B0F1A7-9490-44BC-96E1-4296A31252E2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IFileOperationProgressSink
{
    [PreserveSig] int StartOperations();
    [PreserveSig] int FinishOperations(int result);
    [PreserveSig] int PreRenameItem(uint flags, IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name);
    [PreserveSig] int PostRenameItem(uint flags, IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem created);
    [PreserveSig] int PreMoveItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
    [PreserveSig] int PostMoveItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem created);
    [PreserveSig] int PreCopyItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
    [PreserveSig] int PostCopyItem(uint flags, IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, int result, IShellItem created);
    [PreserveSig] int PreDeleteItem(uint flags, IShellItem item);
    [PreserveSig] int PostDeleteItem(uint flags, IShellItem item, int result, IShellItem created);
    [PreserveSig] int PreNewItem(uint flags, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name);
    [PreserveSig] int PostNewItem(uint flags, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string template, uint attributes, int result, IShellItem created);
    [PreserveSig] int UpdateProgress(uint total, uint done);
    [PreserveSig] int ResetTimer();
    [PreserveSig] int PauseTimer();
    [PreserveSig] int ResumeTimer();
}
