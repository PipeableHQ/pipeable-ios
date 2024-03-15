"use strict";
(function () {
    class PipeablePage {
        constructor() {
            this.elementRegistry = new WeakDomRegistry();
            this.xhrHandles = {};
            this.neworkIdleMonitor = new NetworkActivityMonitor();
            console.log('PipeableJS constructor for frame with url ' + window.location.href);
            // this.attachScriptEventListener();
            this.attachXHRListener();
            this.attachFetchListener();
            this.attachOnErrorListener();
            this.attachMessageBus();
            this.attachOnLoadListeners();
        }
        $(selector, parentElementHash) {
            let parentNode;
            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            const el = parentNode.querySelector(selector);
            if (el) {
                return this.wrapHandle(el);
            }
            else {
                return null;
            }
        }
        $$(selector, parentElementHash) {
            let parentNode;
            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            const elements = parentNode.querySelectorAll(selector);
            const pipeableEls = [];
            for (let i = 0; i < elements.length; i++) {
                const el = elements[i];
                pipeableEls.push(this.wrapHandle(el));
            }
            return pipeableEls;
        }
        $x(xpath, parentElementHash) {
            let parentNode;
            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            const elements = document.evaluate(xpath, parentNode, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const pipeableEls = [];
            for (let i = 0; i < elements.snapshotLength; i++) {
                const el = elements.snapshotItem(i);
                if (el) {
                    pipeableEls.push(this.wrapHandle(el));
                }
            }
            return pipeableEls;
        }
        async waitForSelector(selector, opts) {
            console.log('got wait for selector ' + selector + ' for frame with url ' + window.location.href);
            let parentNode;
            if (opts === null || opts === void 0 ? void 0 : opts.parentElementHash) {
                const parentEl = this.elementRegistry.get(opts.parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            let el = parentNode.querySelector(selector);
            const timeout = (opts === null || opts === void 0 ? void 0 : opts.timeout) || 10000;
            const start = Date.now();
            // console.log(
            //     'got el ',
            //     el,
            //     ' qualify for visibile=' + !!opts?.visible + ' ',
            //     qualifyElement(el, !!opts?.visible),
            // );
            while (!qualifyElement(el, !!(opts === null || opts === void 0 ? void 0 : opts.visible))) {
                if (Date.now() - start > timeout) {
                    throw new Error(`Timeout waiting for selector ${selector}`);
                }
                await new Promise((resolve) => setTimeout(resolve, 500));
                // Re-evaluate
                el = parentNode.querySelector(selector);
                // console.log(
                //     'got el ',
                //     el,
                //     ' qualify for visibile=' + !!opts?.visible + ' ',
                //     qualifyElement(el, !!opts?.visible),
                // );
            }
            return this.wrapHandle(el);
        }
        async waitForXPath(xpath, opts) {
            let parentNode;
            if (opts === null || opts === void 0 ? void 0 : opts.parentElementHash) {
                const parentEl = this.elementRegistry.get(opts.parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            let elements = document.evaluate(xpath, parentNode, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const timeout = (opts === null || opts === void 0 ? void 0 : opts.timeout) || 10000;
            const start = Date.now();
            while (!qualifyElement(elements.snapshotItem(0), !!(opts === null || opts === void 0 ? void 0 : opts.visible))) {
                if (Date.now() - start > timeout) {
                    throw new Error(`Timeout waiting for xpath ${xpath}`);
                }
                await new Promise((resolve) => setTimeout(resolve, 500));
                // Re-evaluate
                elements = document.evaluate(xpath, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            }
            return this.wrapHandle(elements.snapshotItem(0));
        }
        async waitForXHR(url, opts) {
            this.xhrHandles[url] = this.xhrHandles[url] || [];
            const timeout = (opts === null || opts === void 0 ? void 0 : opts.timeout) || 30000;
            console.log('[' + window.location.href + '] ADDED WAITING HANDLE FOR ' + url);
            return new Promise((resolve, reject) => {
                const timeoutId = setTimeout(() => {
                    reject(`Timeout waiting for XHR ${url}`);
                }, timeout);
                const handle = {
                    resolve: (res) => {
                        console.log('[' + window.location.href + '] RECEIVED RESOLVE FOR ' + url);
                        clearTimeout(timeoutId);
                        resolve(JSON.stringify(res));
                        this.xhrHandles[url] = this.xhrHandles[url].filter((h) => h !== handle);
                        if (this.xhrHandles[url].length === 0) {
                            delete this.xhrHandles[url];
                        }
                    },
                    reject: (error) => {
                        clearTimeout(timeoutId);
                        reject(error);
                        this.xhrHandles[url] = this.xhrHandles[url].filter((h) => h !== handle);
                        if (this.xhrHandles[url].length === 0) {
                            delete this.xhrHandles[url];
                        }
                    },
                };
                this.xhrHandles[url].push(handle);
            });
        }
        async click(elementHash, opts) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                // Wait until the element becomes visible.
                const start = Date.now();
                while (!qualifyElement(el, true)) {
                    if (Date.now() - start > opts.timeout) {
                        throw new Error(`Timed out waiting for element to become visible to click: ${elementHash}`);
                    }
                    await new Promise((resolve) => setTimeout(resolve, 100));
                }
                if ('scrollIntoViewIfNeeded' in el) {
                    // this seems to be available in Safari, but for some of the other browser we may need to polyfill.
                    // https://github.com/nuxodin/lazyfill/blob/main/polyfills/Element/prototype/scrollIntoViewIfNeeded.js
                    el.scrollIntoViewIfNeeded();
                }
                else {
                    el.scrollIntoView();
                }
                // Get the bounding rectangle of the visible area of the element
                const rect = el.getBoundingClientRect();
                // Calculate the coordinates of the center of the visible area of the element
                const centerX = rect.left + rect.width / 2;
                const centerY = rect.top + rect.height / 2;
                // Get the innermost element covering the center of the visible area
                const innermostElement = document.elementFromPoint(centerX, centerY);
                // Dispatch a click event on the innermost element
                const clickEvent = new MouseEvent('click', {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    screenX: window.screenX + centerX,
                    screenY: window.screenY + centerY,
                    clientX: window.screenX + centerX,
                    clientY: window.screenY + centerY,
                    ctrlKey: false,
                    altKey: false,
                    shiftKey: false,
                    metaKey: false,
                    button: 0,
                    relatedTarget: null,
                });
                if (!innermostElement) {
                    throw new Error('No innermost element found at the center of the original element -- should not happen');
                }
                // console.log(
                //     'Dispatching click event on innermost element: ' +
                //         innermostElement.tagName +
                //         '#' +
                //         innermostElement.id,
                // );
                // Always fire a focus event before the click event.
                // NOTE: technically should only fire this for a subset
                // of elements (e.g. form elements, links, etc.) or if the tabindex is set,
                // per https://api.jquery.com/focus/
                console.log("HELO!!");
                this._focus(innermostElement);
                innermostElement.dispatchEvent(clickEvent);
                return true;
            }
            return false;
        }
        _focus(el) {
            // Ref:
            // * https://developer.mozilla.org/en-US/docs/Web/API/Element/focus_event
            // * https://api.jquery.com/focus/
            if (el) {
                // emit focus event.
                const event = new FocusEvent('focus', {
                    view: window,
                    bubbles: false,
                    cancelable: false,
                });
                console.log("HERE!!");
                el.dispatchEvent(event);
                if (el instanceof HTMLInputElement) {
                    console.log("firing focus!!");
                    el.focus();
                }
                // emit focusin event.
                const event2 = new FocusEvent('focusin', {
                    view: window,
                    bubbles: true,
                    cancelable: false,
                });
                el.dispatchEvent(event2);
                return true;
            }
            return false;
        }
        focus(elementHash) {
            const el = this.elementRegistry.get(elementHash);
            return this._focus(el);
        }
        blur(elementHash) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                // emit blur event.
                const event = new FocusEvent('blur', {
                    view: window,
                    bubbles: true,
                    cancelable: true,
                });
                el.dispatchEvent(event);
                el.blur();
                return true;
            }
            return false;
        }
        textContent(elementHash) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                return el.textContent;
            }
            return null;
        }
        getAttribute(elementHash, attributeName) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                return el.getAttribute(attributeName);
            }
            return null;
        }
        getElement(elementHash) {
            return this.elementRegistry.get(elementHash);
        }
        submitActiveForm() {
            // Find the currently active element, then the closest form and submit it.
            // If there is no such form or no active element, return false.
            const activeElement = document.activeElement;
            if (!activeElement) {
                return false;
            }
            const form = activeElement.closest('form');
            if (!form) {
                return false;
            }
            const event = new Event('submit', {
                bubbles: true,
                cancelable: true,
            });
            // Dispatch the event
            if (form.dispatchEvent(event)) {
                // If the event was not cancelled, submit the form
                form.submit();
            }
            return true;
        }
        async type(elementHash, text, opts) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                this.focus(elementHash);
                const delay = (opts === null || opts === void 0 ? void 0 : opts.delay) || 0;
                for (let i = 0; i < text.length; i++) {
                    const event = new KeyboardEvent('keydown', {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        key: text[i],
                        code: text[i],
                        charCode: text.charCodeAt(i),
                        keyCode: text.charCodeAt(i),
                    });
                    el.dispatchEvent(event);
                    if (delay > 0) {
                        await new Promise((resolve) => setTimeout(resolve, delay));
                    }
                    const event2 = new KeyboardEvent('keypress', {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        key: text[i],
                        code: text[i],
                        charCode: text.charCodeAt(i),
                        keyCode: text.charCodeAt(i),
                    });
                    el.dispatchEvent(event2);
                    const event3 = new KeyboardEvent('keyup', {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        key: text[i],
                        code: text[i],
                        charCode: text.charCodeAt(i),
                        keyCode: text.charCodeAt(i),
                    });
                    el.dispatchEvent(event3);
                    // Emulate input event
                    let inputEvent = new Event('input', { bubbles: true });
                    el.dispatchEvent(inputEvent);
                    document.execCommand('insertText', false, text[i]);
                    // (el as HTMLInputElement).value = text.slice(0, i + 1);
                }
            }
        }
        sendFrameIDMessage(elementHash, requestId) {
            const el = this.elementRegistry.get(elementHash);
            if (!el) {
                return false;
            }
            // TODO: Perhaps needs a different error message to differentiate.
            if (el.tagName.toLowerCase() !== 'iframe') {
                return false;
            }
            // It's an iframe. We can post a message to get the ID and associate it with the calling request.
            const iframe = el;
            const message = { ctx: 'pipeable', payload: { requestId: requestId } };
            iframe.contentWindow.postMessage(JSON.stringify(message), '*');
            return true;
        }
        wrapHandle(el) {
            let retries = 0;
            do {
                const hash = generateShortRandomHash();
                if (!this.elementRegistry.has(hash)) {
                    this.elementRegistry.set(hash, el);
                    return hash;
                }
                retries++;
                if (retries > 100) {
                    throw new Error('Failed to generate unique hash');
                }
            } while (true);
        }
        version() {
            window.webkit.messageHandlers.handler.postMessage({
                method: 'version',
                requestId: 'asd',
                payload: { version: '0.0.1' },
            });
        }
        attachOnErrorListener() {
            window.onerror = function (message, source, lineno, colno, error) {
                var errorInfo = {
                    message: message,
                    source: source,
                    lineno: lineno,
                    colno: colno,
                    error: error,
                };
                window.webkit.messageHandlers.handler.postMessage({
                    payload: {
                        error: JSON.stringify(errorInfo),
                    },
                });
            };
        }
        attachMessageBus() {
            // Are we in an iframe?
            if (window.self !== window.top) {
                // If so, listen for messages from the parent window
                window.addEventListener('message', function (event) {
                    try {
                        const data = JSON.parse(event.data);
                        if (data.ctx === 'pipeable') {
                            // Forward message to native.
                            window.webkit.messageHandlers.handler.postMessage({
                                ctx: 'pipeable',
                                name: 'frameInfoId',
                                payload: data.payload,
                            });
                        }
                    }
                    catch (e) {
                        console.log('Error parsing message', e);
                    }
                    // window.webkit.messageHandlers.handler.postMessage({
                    //     payload: {
                    //         name: 'frameMessage',
                    //         data: event.data,
                    //     }
                    // });
                }, false);
            }
            else {
                // If not, listen for messages from the iframe
                window.addEventListener('message', function (event) {
                    try {
                        const data = JSON.parse(event.data);
                        if (data.ctx === 'pipeable') {
                            // You can send the received data to Swift using WKScriptMessageHandler here
                            window.webkit.messageHandlers.handler.postMessage({
                                payload: {
                                    name: 'parentMessage',
                                    data: event.data,
                                },
                            });
                        }
                    }
                    catch (e) {
                        console.log('Error parsing message: ' + JSON.stringify(event));
                    }
                });
            }
        }
        // private attachScriptEventListener() {
        //     const observer = new MutationObserver(function (mutations) {
        //         mutations.forEach(function (mutation) {
        //             if (mutation.type === 'childList') {
        //                 for (let i = 0; i < mutation.addedNodes.length; i++) {
        //                     var node = mutation.addedNodes[i] as any;
        //                     if (node.tagName === 'SCRIPT' && node.src) {
        //                         const origOnload = node.onload?.bind(node);
        //                         var message = { payload: { scriptUrl: node.src } };
        //                         node.onload = function () {
        //                             if (origOnload) {
        //                                 origOnload();
        //                             }
        //                             window.webkit.messageHandlers.handler.postMessage(message);
        //                         };
        //                     }
        //                 }
        //             }
        //         });
        //     });
        //     observer.observe(document, {
        //         childList: true,
        //         subtree: true,
        //     });
        //     // Once found and attached, we can stop observing
        //     // observer.disconnect();
        //     console.log('Attached MutationObserver to listen for script loads.');
        // }
        handleXHRResult(xhrResult) {
            console.log('[' + document.location.href + '] Handling XHR Url for: ' + xhrResult.url);
            const reqUrl = xhrResult.url;
            for (let url in this.xhrHandles) {
                const handles = this.xhrHandles[url];
                if ((handles === null || handles === void 0 ? void 0 : handles.length) > 0 && reqUrl.toLowerCase().includes(url.toLowerCase())) {
                    for (let i = 0; i < handles.length; i++) {
                        handles[i].resolve(xhrResult);
                    }
                }
            }
        }
        attachXHRListener() {
            var originalXMLHttpRequest = window.XMLHttpRequest;
            const self = this;
            window.XMLHttpRequest = function () {
                var req = new originalXMLHttpRequest();
                req.addEventListener('loadstart', function () {
                    console.log('[REQUEST START] ' + req.responseURL);
                    self.neworkIdleMonitor.onRequestStart();
                    return true;
                });
                req.addEventListener('loadend', function () {
                    const status = req.status;
                    const bodyRaw = req.response;
                    let body;
                    const contentType = req.getResponseHeader('content-type');
                    const isJson = (contentType === null || contentType === void 0 ? void 0 : contentType.includes('application/json')) || (contentType === null || contentType === void 0 ? void 0 : contentType.includes('text/json'));
                    if (req.responseType === '' || req.responseType === 'text') {
                        body = req.responseText;
                    }
                    else if (req.responseType === 'json') {
                        body = JSON.stringify(req.response);
                    }
                    else if (req.responseType === 'document') {
                        body = req.response.documentElement.outerHTML;
                    }
                    else if (req.responseType === 'arraybuffer' || req.responseType === 'blob') {
                        if (isJson) {
                            // Convert the array buffer to text and return the text to be parsed as JSON.
                            body = new TextDecoder('utf-8').decode(bodyRaw);
                        }
                        else {
                            // Convert ArrayBuffer to Base64 or other textual format
                            body = btoa(String.fromCharCode.apply(null, new Uint8Array(bodyRaw)));
                        }
                    }
                    else {
                        throw new Error('Unsupported response type: ' + req.responseType);
                    }
                    const headers = req.getAllResponseHeaders();
                    const xhrResult = {
                        status: status,
                        url: req.responseURL,
                        body: body,
                        responseType: req.responseType,
                        headers: headers,
                    };
                    self.neworkIdleMonitor.onRequestEnd();
                    console.log('[REQUEST END] ' + req.responseURL, xhrResult);
                    // Dispatch to queue.
                    self.handleXHRResult(xhrResult);
                    // var message = { payload: { url: (event?.currentTarget as any).responseURL } };
                    // window.webkit.messageHandlers.handler.postMessage(message);
                    return true;
                });
                req.addEventListener('error', function (_) {
                    self.neworkIdleMonitor.onRequestEnd();
                    // TODO: Add error handling here.
                });
                req.addEventListener('abort', function (_) {
                    self.neworkIdleMonitor.onRequestEnd();
                    // TODO: Add error handling here.
                });
                return req;
            };
            window.XMLHttpRequest.prototype = originalXMLHttpRequest.prototype;
            // const originalOpen = XMLHttpRequest.prototype.open;
            // XMLHttpRequest.prototype.open = function (method: string, url: string, ...args: any[]) {
            //     // Store the method and URL for later retrieval
            //     this._method = method;
            //     this._requestURL = url;
            //     originalOpen.apply(this, args);
            // } as unknown as typeof XMLHttpRequest.prototype.open;
            console.log('Attached XHR listener.');
        }
        attachFetchListener() {
            const self = this;
            const originalFetch = window.fetch;
            window.fetch = async function (...args) {
                console.log('Fetching:', args); // or any other custom event/logic
                self.neworkIdleMonitor.onRequestStart();
                try {
                    const response = await originalFetch(...args);
                    // Clone the response so we can read it and still return the original
                    const clone = response.clone();
                    // const contentType = clone.headers.get('content-type');
                    const responseBody = await clone.text();
                    const headersArray = [];
                    response.headers.forEach((value, name) => {
                        headersArray.push(name + ': ' + value);
                    });
                    const xhrResult = {
                        status: response.status,
                        url: response.url,
                        body: responseBody,
                        headers: headersArray.join('\n'),
                        responseType: 'text',
                    };
                    self.handleXHRResult(xhrResult);
                    console.log(xhrResult);
                    return response;
                }
                catch (error) {
                    console.error('Fetch error:', error);
                    throw error;
                }
                finally {
                    self.neworkIdleMonitor.onRequestEnd();
                }
            };
        }
        attachOnLoadListeners() {
            window.addEventListener('DOMContentLoaded', () => {
                var _a, _b, _c;
                console.log('PipeableJS load event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'pipeable',
                    name: 'pageLoadStateChange',
                    payload: {
                        state: 'domcontentloaded',
                        url: window.location.href,
                    },
                };
                (_c = (_b = (_a = window.webkit) === null || _a === void 0 ? void 0 : _a.messageHandlers) === null || _b === void 0 ? void 0 : _b.handler) === null || _c === void 0 ? void 0 : _c.postMessage(message);
            });
            window.addEventListener('load', () => {
                var _a, _b, _c;
                console.log('PipeableJS load event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'pipeable',
                    name: 'pageLoadStateChange',
                    payload: {
                        state: 'load',
                        url: window.location.href,
                    },
                };
                (_c = (_b = (_a = window.webkit) === null || _a === void 0 ? void 0 : _a.messageHandlers) === null || _b === void 0 ? void 0 : _b.handler) === null || _c === void 0 ? void 0 : _c.postMessage(message);
                // Once we're loaded, we start monitoring network activity and wait until it's idle.
                this.neworkIdleMonitor.start();
            });
            this.neworkIdleMonitor.setOnIdle(() => {
                var _a, _b, _c;
                console.log('PipeableJS networkidle event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'pipeable',
                    name: 'pageLoadStateChange',
                    payload: {
                        state: 'networkidle',
                        url: window.location.href,
                    },
                };
                (_c = (_b = (_a = window.webkit) === null || _a === void 0 ? void 0 : _a.messageHandlers) === null || _b === void 0 ? void 0 : _b.handler) === null || _c === void 0 ? void 0 : _c.postMessage(message);
            });
        }
    }
    class NetworkActivityMonitor {
        constructor() {
            this.requestsInFlight = 0;
            this.idleTimeout = 500;
            this.onIdle = () => { };
        }
        setOnIdle(onIdle) {
            this.onIdle = onIdle;
        }
        onRequestStart() {
            this.requestsInFlight++;
            this.resetIdleTimeout();
        }
        onRequestEnd() {
            this.requestsInFlight--;
            this.resetIdleTimeout();
        }
        start() {
            this.resetIdleTimeout();
        }
        resetIdleTimeout() {
            if (this.timeoutId) {
                clearTimeout(this.timeoutId);
            }
            if (this.requestsInFlight === 0) {
                this.timeoutId = setTimeout(() => {
                    this.onIdle();
                }, this.idleTimeout);
            }
        }
    }
    class WeakDomRegistry {
        constructor() {
            this.keyToObjectMap = new Map(); // Maps strings to objects
            this.objectToDomMap = new WeakMap(); // Maps objects to DOM elements
        }
        set(id, element) {
            let keyObject = {};
            this.keyToObjectMap.set(id, keyObject);
            this.objectToDomMap.set(keyObject, element);
        }
        get(id) {
            let keyObject = this.keyToObjectMap.get(id);
            if (keyObject) {
                const el = this.objectToDomMap.get(keyObject);
                if (el) {
                    if (!el.isConnected) {
                        throw new Error('Element not attached to DOM');
                    }
                    return el;
                }
            }
            return undefined;
        }
        delete(id) {
            let keyObject = this.keyToObjectMap.get(id);
            if (keyObject) {
                this.objectToDomMap.delete(keyObject);
                this.keyToObjectMap.delete(id);
            }
        }
        has(id) {
            return this.keyToObjectMap.has(id) && this.objectToDomMap.has(this.keyToObjectMap.get(id));
        }
    }
    function generateShortRandomHash(length = 6) {
        const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        let result = '';
        for (let i = 0; i < length; i++) {
            result += chars[Math.floor(Math.random() * chars.length)];
        }
        return result;
    }
    function isElementAttached(el) {
        return document.body.contains(el);
    }
    function isElementVisible(el) {
        let currentElement = el;
        let level = 0;
        // Check element style and its ancestors
        while (currentElement) {
            // Check if the element is within the viewport
            if (level === 0) {
                const rect = currentElement.getBoundingClientRect();
                // Check if the element is within the viewport
                if (rect.width <= 0 || rect.height <= 0) {
                    // DEBUG:
                    // console.log('level[' + level + '] -> size is 0');
                    return false;
                }
            }
            const style = getComputedStyle(currentElement);
            if (style.display === 'contents') {
                // If the element is a "contents" element, it doesn't enforce style, skip.
                currentElement = currentElement.parentElement;
                level++;
                continue;
            }
            if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity) === 0) {
                // If we need to debug why something is not visible.
                // DEBUG:
                // let reason = {
                //     display: style.display,
                //     visibility: style.visibility,
                //     opacity: style.opacity,
                //     width: style.width,
                //     height: style.height,
                // };
                // console.log(
                //     '[level ' + level + '] -> class: ' + classes + ', hidden ' + JSON.stringify(reason, null, 4),
                // );
                return false;
            }
            // Continue checking the parents to see if any of those impose visibility restrictions.
            currentElement = currentElement.parentElement;
            level++;
        }
        return true;
    }
    function qualifyElement(element, visible) {
        if (element) {
            if (visible && !isElementVisible(element)) {
                // console.log('Disqualified element because it is not visible');
                return false;
            }
            if (!isElementAttached(element)) {
                // console.log('Disqualified element because it is not attached');
                return false;
            }
            return true;
        }
        // console.log('Disqualified element because it is null');
        return false;
    }
    // Expose this directly.
    if (!window.PipeableJS) {
        window.PipeableJS = new PipeablePage();
    }
})();
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoicGlwZWFibGUuanMiLCJzb3VyY2VSb290IjoiIiwic291cmNlcyI6WyIuLi9zcmMvcGlwZWFibGUudHMiXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IjtBQUFBLENBQUM7SUFDRyxNQUFNLFlBQVk7UUFZZDtZQVhRLG9CQUFlLEdBQUcsSUFBSSxlQUFlLEVBQUUsQ0FBQztZQUV4QyxlQUFVLEdBS2QsRUFBRSxDQUFDO1lBRUMsc0JBQWlCLEdBQUcsSUFBSSxzQkFBc0IsRUFBRSxDQUFDO1lBR3JELE9BQU8sQ0FBQyxHQUFHLENBQUMsNENBQTRDLEdBQUcsTUFBTSxDQUFDLFFBQVEsQ0FBQyxJQUFJLENBQUMsQ0FBQztZQUVqRixvQ0FBb0M7WUFDcEMsSUFBSSxDQUFDLGlCQUFpQixFQUFFLENBQUM7WUFDekIsSUFBSSxDQUFDLG1CQUFtQixFQUFFLENBQUM7WUFFM0IsSUFBSSxDQUFDLHFCQUFxQixFQUFFLENBQUM7WUFDN0IsSUFBSSxDQUFDLGdCQUFnQixFQUFFLENBQUM7WUFFeEIsSUFBSSxDQUFDLHFCQUFxQixFQUFFLENBQUM7UUFDakMsQ0FBQztRQUVELENBQUMsQ0FBQyxRQUFnQixFQUFFLGlCQUEwQjtZQUMxQyxJQUFJLFVBQXNCLENBQUM7WUFFM0IsSUFBSSxpQkFBaUIsRUFBRTtnQkFDbkIsTUFBTSxRQUFRLEdBQUcsSUFBSSxDQUFDLGVBQWUsQ0FBQyxHQUFHLENBQUMsaUJBQWlCLENBQUMsQ0FBQztnQkFDN0QsVUFBVSxHQUFHLFFBQVEsSUFBSSxRQUFRLENBQUM7YUFDckM7aUJBQU07Z0JBQ0gsVUFBVSxHQUFHLFFBQVEsQ0FBQzthQUN6QjtZQUVELE1BQU0sRUFBRSxHQUFHLFVBQVUsQ0FBQyxhQUFhLENBQUMsUUFBUSxDQUFDLENBQUM7WUFDOUMsSUFBSSxFQUFFLEVBQUU7Z0JBQ0osT0FBTyxJQUFJLENBQUMsVUFBVSxDQUFDLEVBQWlCLENBQUMsQ0FBQzthQUM3QztpQkFBTTtnQkFDSCxPQUFPLElBQUksQ0FBQzthQUNmO1FBQ0wsQ0FBQztR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