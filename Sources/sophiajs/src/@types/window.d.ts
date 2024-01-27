interface Window {
    webkit: any;
}

interface Document {
    execCommand(command: string, showUI?: boolean, value?: string): any;
}
