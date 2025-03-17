// Authentication utilities

// Check if user is logged in
function isLoggedIn() {
    const token = localStorage.getItem('token');
    if (!token) {
        return false;
    }
    
    // Check if token is expired
    try {
        // JWT tokens are in format: header.payload.signature
        // We need to decode the payload (middle part)
        const payload = token.split('.')[1];
        const decodedPayload = JSON.parse(atob(payload));
        
        // Check if token has expired
        const currentTime = Math.floor(Date.now() / 1000);
        if (decodedPayload.exp && decodedPayload.exp < currentTime) {
            // Token has expired, remove it
            localStorage.removeItem('token');
            return false;
        }
        
        return true;
    } catch (error) {
        console.error('Error checking token:', error);
        // If there's an error parsing the token, consider it invalid
        localStorage.removeItem('token');
        return false;
    }
}

// Update navigation based on login status
function updateNavigation() {
    const navElement = document.getElementById('main-nav');
    if (!navElement) return;
    
    // Remove any existing auth-links container
    const existingAuthLinks = navElement.querySelector('.auth-links');
    if (existingAuthLinks) {
        existingAuthLinks.remove();
    }
    
    const authLinksContainer = document.createElement('div');
    authLinksContainer.className = 'auth-links';
    
    if (isLoggedIn()) {
        // User is logged in, show Dashboard and Logout
        authLinksContainer.innerHTML = `
            <a href="/static/dashboard.html" class="nav-link">Dashboard</a>
            <a href="#" class="register-btn" id="logout-btn">Logout</a>
        `;
    } else {
        // User is not logged in, show Login and Register
        authLinksContainer.innerHTML = `
            <a href="/static/login.html" class="nav-link">Login</a>
            <a href="/static/register.html" class="register-btn">Register</a>
        `;
    }
    
    // Add auth links to navigation
    navElement.appendChild(authLinksContainer);
    
    // Add event listener to logout button if it exists
    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', logout);
    }
    
    // Update CTA button if it exists
    const ctaAccount = document.getElementById('cta-account');
    if (ctaAccount) {
        if (isLoggedIn()) {
            ctaAccount.textContent = 'Go to Dashboard';
            ctaAccount.href = '/static/dashboard.html';
        } else {
            ctaAccount.textContent = 'Create an Account';
            ctaAccount.href = '/static/register.html';
        }
    }
}

// Logout function
function logout(e) {
    if (e) e.preventDefault();
    localStorage.removeItem('token');
    // Update navigation immediately after logout
    updateNavigation();
    // Redirect to home page
    window.location.href = '/';
}

// Get the authentication token
function getAuthToken() {
    return localStorage.getItem('token');
}

// Check if user should be redirected to login
function redirectIfNotLoggedIn() {
    if (!isLoggedIn()) {
        window.location.href = '/static/login.html';
        return false;
    }
    return true;
}

// Check if user should be redirected to dashboard
function redirectIfLoggedIn() {
    if (isLoggedIn()) {
        window.location.href = '/';
        return true;
    }
    return false;
}

// Initialize authentication on page load
document.addEventListener('DOMContentLoaded', updateNavigation); 